#!/usr/bin/env python3
"""Fetch every source in `sources.json` into `raw/`, and report what moved.

The corpus is committed, so `git diff` after a run *is* the update report; what
this prints on top is the part a diff states badly -- which thread gained
comments, which one changed state, and which links turned up that nothing
tracks yet.

Run it with no arguments to refresh everything. `--check` fetches nothing that
would be written and reports what a real run would change; it is the cheap
answer to "is the knowledge base stale?".
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

# Set from `--dir`. The Nix wrapper runs the script out of the store, where it
# cannot write, and points it at the working tree instead.
HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
STATE = HERE / "state"


def set_dir(directory: Path) -> None:
    global HERE, RAW, STATE
    HERE = directory.resolve()
    RAW = HERE / "raw"
    STATE = HERE / "state"

USER_AGENT = "modular-services-crowdsource-sync"

# Distinguishes "the server says nothing changed" from "there is nothing here".
NOT_MODIFIED = object()


# ---------------------------------------------------------------------------
# pruning
#
# What lands in `raw/` is the API response with a fixed set of keys removed.
# Those keys carry no discussion: they are either derivable from the ids that
# stay (`*_url`), opaque (`node_id`), or a rendering of a body that is kept
# verbatim anyway (`body_html`, `body_text`). Dropping them cuts the corpus by
# roughly two thirds and, more to the point, keeps a diff between two syncs
# readable -- an avatar URL that gained a `?v=4` is churn nobody can act on.
# `--no-prune` turns this off for anyone who wants the response untouched.
# ---------------------------------------------------------------------------

PRUNE_KEYS = {
    "node_id",
    "gravatar_id",
    "avatar_url",
    "url",
    "html_url",  # restored on the top-level record after pruning, and only there
    "followers_url",
    "following_url",
    "gists_url",
    "starred_url",
    "subscriptions_url",
    "organizations_url",
    "repos_url",
    "events_url",
    "received_events_url",
    "comments_url",
    "labels_url",
    "milestone_url",
    "timeline_url",
    "issue_url",
    "pull_request_url",
    "review_comments_url",
    "review_comment_url",
    "commits_url",
    "statuses_url",
    "contents_url",
    "compare_url",
    "merges_url",
    "archive_url",
    "downloads_url",
    "issue_comment_url",
    "issue_events_url",
    "assignees_url",
    "branches_url",
    "blobs_url",
    "git_tags_url",
    "git_refs_url",
    "trees_url",
    "hooks_url",
    "keys_url",
    "collaborators_url",
    "teams_url",
    "forks_url",
    "languages_url",
    "stargazers_url",
    "contributors_url",
    "subscribers_url",
    "notifications_url",
    "deployments_url",
    "releases_url",
    "ssh_url",
    "clone_url",
    "git_url",
    "svn_url",
    "mirror_url",
    "body_html",
    "body_text",
    "title_html",
    "performed_via_github_app",
    "user_view_type",
    "author_association",
    "_links",
}

# The timeline is kept only for what the rest of the record does not already
# say: which commits and issues point here, what the title used to be, and when
# the thing opened and closed. `commented` and `reviewed` are deliberately out
# -- they restate `comments` and `reviews` in full, and did so 2113 times over
# a corpus of 173 items.
TIMELINE_EVENTS = {
    "cross-referenced",
    "referenced",
    "connected",
    "disconnected",
    "marked_as_duplicate",
    "unmarked_as_duplicate",
    "renamed",
    "closed",
    "reopened",
    "merged",
    "transferred",
    "converted_to_discussion",
}


# A pull request carries the whole repository object three times over -- on
# `base`, on `head` and on the issue -- and that object holds nixpkgs' live
# star, fork and open-issue counts. Left in, every refresh rewrites every pull
# request file with numbers nobody asked about, and the diff that is supposed
# to *be* the report becomes a hundred files of fork counts. So a
# repository-shaped dict is reduced to what identifies it.
REPO_KEEP = ("full_name", "id", "private", "fork", "archived", "default_branch")


def is_repo(d: dict) -> bool:
    return "full_name" in d and "owner" in d and "stargazers_count" in d


def prune(value):
    if isinstance(value, dict):
        if is_repo(value):
            return {k: value[k] for k in REPO_KEEP if k in value}
        out = {}
        for k, v in value.items():
            if k in PRUNE_KEYS:
                continue
            out[k] = prune(v)
        return out
    if isinstance(value, list):
        return [prune(v) for v in value]
    return value


# ---------------------------------------------------------------------------
# transports
# ---------------------------------------------------------------------------


class Fetcher:
    """`gh api` for GitHub, plain HTTP for everything else, with one retry
    policy over both. GitHub's secondary rate limit answers a burst with a 403
    rather than a 429, so a retry that only looked at the status code would give
    up on a corpus this size.

    Every request that can be conditional is: the ETag of the last response is
    replayed as `If-None-Match`, and a 304 costs no rate-limit quota at all.
    That is what makes checking a corpus this size for updates nearly free --
    a full fetch is ~650 requests against an hourly limit of 5000, while a
    check where nothing moved is ~150 requests that all come back 304 and
    never count against it. GitHub also honours `If-Modified-Since`, but the ETag is
    both stronger and what the API hands back unasked.

    The search endpoints are the tight constraint instead: 30 per *minute*, and
    no conditional form. `pace_search` keeps a run under it.
    """

    def __init__(self, verbose: bool = False, etags: dict | None = None):
        self.verbose = verbose
        self.requests = 0
        self.counted = 0
        self.not_modified = 0
        self.etags = etags if etags is not None else {}
        self.search_times: list[float] = []
        self.rate_remaining: int | None = None

    def pace_search(self) -> None:
        """Block until another search request fits in the 30-per-minute window."""
        now = time.monotonic()
        self.search_times = [t for t in self.search_times if now - t < 60]
        if len(self.search_times) >= 28:
            wait = 61 - (now - self.search_times[0])
            if wait > 0:
                print(f"  . search quota: waiting {wait:.0f}s", file=sys.stderr)
                time.sleep(wait)
                now = time.monotonic()
                self.search_times = [t for t in self.search_times if now - t < 60]
        self.search_times.append(time.monotonic())

    def conditional(self, path: str, replay: bool = True):
        """Single-page GET, recording the ETag of what comes back.

        Returns `(True, data)` when the resource changed and `(False, None)`
        when the server answered 304. A resource never seen before always
        counts as changed. `replay=False` asks for the body unconditionally
        while still learning its validator, which is how an endpoint fetched
        for its content ends up cheap to check next time.
        """
        etag = self.etags.get(path) if replay else None
        cmd = ["gh", "api", "-i", path]
        if etag:
            cmd += ["-H", f"If-None-Match: {etag}"]
        for attempt in range(5):
            self.requests += 1
            self.log(f"gh api -i {path}{' (cond)' if etag else ''}")
            proc = subprocess.run(cmd, capture_output=True, text=True)
            # `gh api` exits non-zero on any status outside 2xx, 304 included,
            # having already written the response head to stdout. So the head is
            # what decides, not the exit code.
            raw = proc.stdout.replace("\r\n", "\n")
            if not raw.startswith("HTTP/"):
                err = (proc.stderr or "").lower()
                if "404" in err or "not found" in err:
                    return True, None
                if attempt == 4:
                    raise RuntimeError(f"gh api {path} failed: {proc.stderr.strip()}")
                wait = 5 * (attempt + 1) ** 2
                print(f"  ! {path}: {proc.stderr.strip()[:120]}; retry in {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            head, _, body = raw.partition("\n\n")
            status = 0
            tags: list[str] = []
            for line in head.split("\n"):
                if line.startswith("HTTP/"):
                    status = int(line.split()[1])
                elif line.lower().startswith("etag:"):
                    tags.append(line.split(":", 1)[1].strip())
                elif line.lower().startswith("x-ratelimit-remaining:"):
                    self.rate_remaining = int(line.split(":", 1)[1].strip())
            # Only a 200 teaches a validator. GitHub answers 304 with the same
            # tag stripped of its `W/` prefix and then refuses to match the
            # stripped form on the next request, so storing it would turn every
            # second run back into a full fetch.
            if status == 304:
                self.not_modified += 1
                return False, None
            if tags:
                # The last one, so a redirect's intermediate head cannot win.
                self.etags[path] = tags[-1]
            if status == 404:
                return True, None
            if status >= 400:
                if attempt == 4:
                    raise RuntimeError(f"gh api {path}: HTTP {status}")
                wait = 5 * (attempt + 1) ** 2
                print(f"  ! {path}: HTTP {status}; retry in {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            self.counted += 1
            return True, json.loads(body) if body.strip() else None
        return True, None

    def log(self, msg: str) -> None:
        if self.verbose:
            print(f"  . {msg}", file=sys.stderr)

    def gh(self, path: str, paginate: bool = False):
        cmd = ["gh", "api", path]
        if paginate:
            cmd += ["--paginate", "--slurp"]
        for attempt in range(5):
            self.requests += 1
            self.log(f"gh api {path}{' --paginate' if paginate else ''}")
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode == 0:
                self.counted += 1
                out = proc.stdout.strip()
                if not out:
                    return None
                data = json.loads(out)
                # `--slurp` yields a list of pages; flatten to a list of items.
                if paginate and isinstance(data, list):
                    flat = []
                    for page in data:
                        if isinstance(page, list):
                            flat.extend(page)
                        elif isinstance(page, dict) and "items" in page:
                            # The search endpoints wrap each page in
                            # {total_count, incomplete_results, items}.
                            flat.extend(page["items"])
                        else:
                            flat.append(page)
                    return flat
                return data
            err = (proc.stderr or "").lower()
            if "404" in err or "not found" in err:
                return None
            if attempt == 4:
                raise RuntimeError(f"gh api {path} failed: {proc.stderr.strip()}")
            wait = 5 * (attempt + 1) ** 2
            print(f"  ! {path}: {proc.stderr.strip()[:120]}; retry in {wait}s", file=sys.stderr)
            time.sleep(wait)

    def http(self, url: str, as_json: bool = True, conditional: bool = False):
        """Plain GET. With `conditional`, replays the stored ETag and returns
        the sentinel `NOT_MODIFIED` on a 304. Discourse and the project board
        send `cache-control: no-store`, so only the pad benefits; the support is
        here because a source that gains a validator should not need new code."""
        headers = {"User-Agent": USER_AGENT}
        if conditional and url in self.etags:
            headers["If-None-Match"] = self.etags[url]
        for attempt in range(5):
            self.requests += 1
            self.log(f"GET {url}")
            req = urllib.request.Request(url, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    body = resp.read().decode("utf-8")
                    if conditional and resp.headers.get("ETag"):
                        self.etags[url] = resp.headers["ETag"]
                return json.loads(body) if as_json else body
            except urllib.error.HTTPError as e:
                if e.code == 304:
                    self.not_modified += 1
                    return NOT_MODIFIED
                if e.code == 404:
                    return None
                if attempt == 4:
                    raise
            except Exception:
                if attempt == 4:
                    raise
            time.sleep(5 * (attempt + 1))


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------


@dataclass
class Report:
    """What a run changed, in the terms the corpus is read in."""

    new: list[str] = field(default_factory=list)
    updated: list[str] = field(default_factory=list)
    unchanged: int = 0
    removed: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def write_json(path: Path, data, check: bool) -> str:
    """Write `data` if it differs. Returns "new", "updated" or "same"."""
    text = json.dumps(data, indent=1, sort_keys=True, ensure_ascii=False) + "\n"
    if path.exists():
        if path.read_text(encoding="utf-8") == text:
            return "same"
        state = "updated"
    else:
        state = "new"
    if not check:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return state


def write_text(path: Path, text: str, check: bool) -> str:
    if path.exists():
        if path.read_text(encoding="utf-8") == text:
            return "same"
        state = "updated"
    else:
        state = "new"
    if not check:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return state


# ---------------------------------------------------------------------------
# GitHub items
# ---------------------------------------------------------------------------

ITEM_RE = re.compile(r"^(?P<owner>[\w.-]+)/(?P<repo>[\w.-]+)#(?P<number>\d+)$")


def item_path(owner: str, repo: str, number: int) -> Path:
    return RAW / "github" / owner / repo / f"{number}.json"


def fetch_github_item(
    f: Fetcher, ref: str, prune_on: bool, existing: dict | None
) -> tuple[dict | None, bool]:
    """Fetch one issue or pull request. Returns `(record, fetched)`.

    The expensive part is the three-to-six list requests per item, so they are
    gated behind a single conditional GET of `issues/{n}`. A pull request is an
    issue underneath -- the two endpoints report the same `updated_at`, moved
    by a comment, an edit, a review, a review comment, a label or a state
    change alike -- so one 304 covers the lot.

    `pulls/{n}` is deliberately *not* also gated on, though it was at first: its
    payload embeds the repository object, complete with the live star and fork
    counts of whichever repository the pull request is against. Those move
    every few minutes on nixpkgs, taking the ETag with them, so gating on it
    meant refetching a hundred pull requests every run to write byte-identical
    files.

    `--force` skips the gate for anyone who does not want to rely on this.
    """
    m = ITEM_RE.match(ref)
    if not m:
        raise ValueError(f"not an item reference: {ref!r}")
    owner, repo, number = m["owner"], m["repo"], int(m["number"])
    base = f"repos/{owner}/{repo}"

    changed, issue = f.conditional(f"{base}/issues/{number}")
    if not changed and existing is not None:
        return existing, False
    if issue is None:
        if not changed:
            # An ETag without the file it described: fetch unconditionally.
            _, issue = f.conditional(f"{base}/issues/{number}", replay=False)
        if issue is None:
            return None, True

    is_pr = "pull_request" in issue

    record: dict = {
        "ref": ref,
        "kind": "pull_request" if is_pr else "issue",
        "issue": issue,
        "comments": f.gh(f"{base}/issues/{number}/comments?per_page=100", paginate=True) or [],
        "timeline": [
            e
            for e in (f.gh(f"{base}/issues/{number}/timeline?per_page=100", paginate=True) or [])
            if e.get("event") in TIMELINE_EVENTS
        ],
    }
    if is_pr:
        # Through `conditional` rather than `gh`, so the next run can gate the
        # five requests below this one on a 304 for it.
        _, record["pull_request"] = f.conditional(f"{base}/pulls/{number}", replay=False)
        record["reviews"] = f.gh(f"{base}/pulls/{number}/reviews?per_page=100", paginate=True) or []
        record["review_comments"] = (
            f.gh(f"{base}/pulls/{number}/comments?per_page=100", paginate=True) or []
        )
    if prune_on:
        record = prune(record)
        # The one URL worth keeping per record: where a reader goes to read it.
        record["html_url"] = issue.get("html_url") or (
            f"https://github.com/{owner}/{repo}/{'pull' if is_pr else 'issues'}/{number}"
        )
    return record, True


# ---------------------------------------------------------------------------
# GitHub project boards
#
# A fine-grained token cannot read organization ProjectsV2, and asking for a
# classic token with `read:project` just to read a public board is a poor trade.
# The board's own page carries its full state in a `memex-*` JSON island, which
# is what the browser renders from, so that is what this reads.
# ---------------------------------------------------------------------------

ISLAND_RE = r'<script type="application/json" id="{}">(.*?)</script>'


def fetch_github_project(f: Fetcher, org: str, number: int) -> dict | None:
    import html as html_mod

    url = f"https://github.com/orgs/{org}/projects/{number}"
    page = f.http(url, as_json=False)
    if page is None:
        return None

    def island(name):
        m = re.search(ISLAND_RE.format(re.escape(name)), page, re.S)
        return json.loads(html_mod.unescape(m.group(1))) if m else None

    data = island("memex-data") or {}
    items = island("memex-paginated-items-data") or {}
    columns = island("memex-columns-data") or []

    # `memexProjectColumnValues` is a list of {columnId, value} pairs; flattening
    # it to a mapping is what makes a board item comparable between two syncs.
    def flatten(node):
        values = {
            v.get("memexProjectColumnId"): v.get("value")
            for v in node.get("memexProjectColumnValues", [])
        }
        title = (values.get("Title") or {})
        repo = (values.get("Repository") or {})
        return {
            "number": title.get("number"),
            "title": (title.get("title") or {}).get("raw"),
            "repository": repo.get("nameWithOwner"),
            "url": (node.get("content") or {}).get("url"),
            "contentType": node.get("contentType"),
            "state": node.get("state"),
            "status": values.get("Status"),
            "assignees": [a.get("login") for a in (values.get("Assignees") or [])],
            "updatedAt": node.get("updatedAt"),
            "issueCreatedAt": node.get("issueCreatedAt"),
            "fields": {
                k: v for k, v in values.items() if k not in ("Title", "Repository", "Assignees")
            },
        }

    groups = []
    status_names = {}
    for column in columns:
        if column.get("nameSlug") == "status":
            for option in ((column.get("settings") or {}).get("options") or []):
                status_names[option["id"]] = option["name"]

    for group in items.get("groupedItems", []):
        gid = group.get("groupId")
        meta = next(
            (
                g
                for g in (items.get("groups", {}).get("nodes") or [])
                if g.get("groupId") == gid
            ),
            {},
        )
        groups.append(
            {
                "group": meta.get("groupValue"),
                "description": (meta.get("groupMetadata") or {}).get("description"),
                "items": [flatten(n) for n in group.get("nodes", [])],
            }
        )

    # `memex-data` is the project itself, not a wrapper around it.
    return {
        "org": org,
        "number": number,
        "url": url,
        "title": data.get("title"),
        "description": data.get("shortDescription") or data.get("description"),
        "public": data.get("public"),
        "closed": data.get("closedAt") is not None,
        "createdAt": data.get("createdAt"),
        "totalCount": (items.get("totalCount") or {}).get("value"),
        "statusOptions": [
            {"id": k, "name": v} for k, v in sorted(status_names.items(), key=lambda kv: kv[1])
        ],
        "columns": [
            {"name": c.get("name"), "dataType": c.get("dataType"), "visible": c.get("visible")}
            for c in columns
        ],
        "groups": groups,
    }


# ---------------------------------------------------------------------------
# Discourse and HedgeDoc
# ---------------------------------------------------------------------------


# Discourse hands out twenty posts per request and viewer-dependent flags on
# every one of them. A topic is therefore read page by page, and the flags that
# describe *this* reader rather than the post are dropped: they would otherwise
# make every sync report a change on threads nobody touched.
DISCOURSE_POST_DROP = {
    "cooked",
    "avatar_template",
    "actions_summary",
    "yours",
    "can_edit",
    "can_delete",
    "can_recover",
    "can_wiki",
    "can_see_hidden_post",
    "can_view_edit_history",
    "read",
    "readers_count",
    "bookmarked",
    "score",
    "topic_slug",
    "display_username",
    "flair_url",
    "flair_bg_color",
    "flair_color",
    "flair_group_id",
    "trust_level",
    "admin",
    "moderator",
    "staff",
    "hidden",
    "user_deleted",
    "edit_reason",
    "reviewable_id",
    "reviewable_score_count",
    "reviewable_score_pending_count",
    # Counters that move because somebody opened the page, not because
    # somebody said something.
    "reads",
    "calendar_details",
    "mentioned_users",
    "post_url",
    "notice",
}

# `views` is deliberately absent for the same reason as a post's `reads`.
DISCOURSE_TOPIC_KEYS = (
    "id title slug posts_count created_at last_posted_at category_id tags "
    "like_count reply_count word_count closed archived archetype"
).split()


def fetch_discourse_topic(f: Fetcher, host: str, topic: int) -> dict | None:
    first = f.http(f"https://{host}/t/{topic}.json?include_raw=true")
    if first is None:
        return None
    total = first.get("posts_count") or 0
    posts = list((first.get("post_stream") or {}).get("posts") or [])
    page = 1
    # `posts_count` counts deleted posts that the stream omits, so the loop also
    # stops when a page adds nothing rather than only when the count is reached.
    while len(posts) < total and page < 50:
        page += 1
        more = f.http(f"https://{host}/t/{topic}.json?include_raw=true&page={page}")
        batch = list(((more or {}).get("post_stream") or {}).get("posts") or [])
        known = {p["id"] for p in posts}
        fresh = [p for p in batch if p["id"] not in known]
        if not fresh:
            break
        posts.extend(fresh)

    for post in posts:
        for k in DISCOURSE_POST_DROP:
            post.pop(k, None)

    return {
        "host": host,
        "url": f"https://{host}/t/{first.get('slug')}/{first.get('id')}",
        **{k: first.get(k) for k in DISCOURSE_TOPIC_KEYS},
        "posts_fetched": len(posts),
        "posts": sorted(posts, key=lambda p: p.get("post_number", 0)),
    }


def fetch_hedgedoc(f: Fetcher, url: str):
    return f.http(url.rstrip("/") + "/download", as_json=False, conditional=True)


# ---------------------------------------------------------------------------
# link extraction
#
# Every root names more sources than the manifest does. Rather than crawl those
# automatically -- one nixpkgs thread links half of nixpkgs -- a run collects
# what it saw, subtracts what is already tracked, and leaves the rest in
# `state/discovered.json` ordered by how often it came up. Promoting a line of
# that file into `sources.json` is how the closure grows, and it stays a
# judgement someone made rather than a crawl depth someone picked.
# ---------------------------------------------------------------------------

GH_LINK_RE = re.compile(
    r"https?://github\.com/([\w.-]+)/([\w.-]+)/(?:issues|pull)/(\d+)", re.I
)
DISCOURSE_LINK_RE = re.compile(r"https?://(discourse\.nixos\.org)/t/(?:[\w%-]+/)?(\d+)", re.I)
BARE_REF_RE = re.compile(r"(?<![\w/])([\w.-]+/[\w.-]+)#(\d+)\b")


# Only what somebody wrote counts as a mention. A `diff_hunk` on a review
# comment repeats the surrounding lines of the patch on every comment in the
# file, so a link that happens to sit in a nearby source line would otherwise
# outrank the links people actually posted.
TEXT_FIELDS = {"body", "raw", "title", "description", "html_url", "url", "message"}


def texts(value) -> list:
    """Every human-written string in a record, ignoring machine-generated ones."""
    out = []
    if isinstance(value, dict):
        for k, v in value.items():
            if k == "diff_hunk":
                continue
            if isinstance(v, str):
                if k in TEXT_FIELDS:
                    out.append(v)
            else:
                out.extend(texts(v))
    elif isinstance(value, list):
        for v in value:
            out.extend(texts(v))
    elif isinstance(value, str):
        out.append(value)
    return out


def harvest_links(blob: str, counts: dict[str, int]) -> None:
    for owner, repo, number in GH_LINK_RE.findall(blob):
        counts[f"{owner}/{repo}#{int(number)}"] = counts.get(f"{owner}/{repo}#{int(number)}", 0) + 1
    for host, topic in DISCOURSE_LINK_RE.findall(blob):
        key = f"discourse:{host}/t/{topic}"
        counts[key] = counts.get(key, 0) + 1
    for repo, number in BARE_REF_RE.findall(blob):
        if "/" in repo and not repo.endswith((".md", ".nix", ".py")):
            key = f"{repo}#{int(number)}"
            counts[key] = counts.get(key, 0) + 1



# ---------------------------------------------------------------------------
# the index
#
# `raw/` is a file tree of numbers; INDEX.md is the same corpus with titles,
# states and the reason each item is here. It is generated, never edited: the
# reasons come from `why` in sources.json, so that is where to write one.
# Nothing in it carries a timestamp -- a generated file that changes on every
# run teaches a reader to ignore its diff.
# ---------------------------------------------------------------------------


def sort_key(ref: str):
    repo, _, number = ref.partition("#")
    return (repo.lower(), int(number) if number.isdigit() else 0)


def write_index(manifest: dict, check: bool) -> None:
    why = {s["id"]: s.get("why", "") for s in manifest["sources"]}
    lines: list[str] = []
    add = lines.append

    add("# The crowdsourced design record, indexed")
    add("")
    add("Generated by `sync.py`. Every entry links its source and names the")
    add("`sources.json` entries that reached it; `why` there is the standing")
    add("answer to what an entry is doing in the corpus.")
    add("")

    items: dict[str, dict] = {}
    for path in sorted(RAW.glob("github/*/*/*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        items[record["ref"]] = record

    by_repo: dict[str, list] = {}
    for ref, record in items.items():
        by_repo.setdefault(ref.split("#")[0], []).append(ref)

    add(f"## GitHub issues and pull requests ({len(items)})")
    add("")
    for repo in sorted(by_repo, key=str.lower):
        refs = sorted(by_repo[repo], key=sort_key)
        add(f"### {repo} ({len(refs)})")
        add("")
        add("| item | title | state | comments | last activity | reached by |")
        add("| --- | --- | --- | --- | --- | --- |")
        for ref in refs:
            r = items[ref]
            issue = r["issue"]
            state = issue.get("state", "")
            if r["kind"] == "pull_request" and (r.get("pull_request") or {}).get("merged"):
                state = "merged"
            total = len(r.get("comments", [])) + len(r.get("review_comments", []))
            title = (issue.get("title") or "").replace("|", "\\|")
            add(
                f"| [#{ref.split('#')[1]}]({r.get('html_url', '')}) | {title} | {state} | "
                f"{total} | {(issue.get('updated_at') or '')[:10]} | "
                f"{', '.join(r.get('sources', []))} |"
            )
        add("")

    topics = sorted(RAW.glob("discourse/*/*.json"), key=lambda p: int(p.stem))
    if topics:
        add(f"## Discourse ({len(topics)})")
        add("")
        add("| topic | posts | last post | reached by |")
        add("| --- | --- | --- | --- |")
        for path in topics:
            t = json.loads(path.read_text(encoding="utf-8"))
            add(
                f"| [{(t.get('title') or '').replace('|', chr(92) + '|')}]({t.get('url')}) | "
                f"{t.get('posts_fetched')} | {(t.get('last_posted_at') or '')[:10]} | "
                f"{', '.join(t.get('sources', []))} |"
            )
        add("")

    for path in sorted(RAW.glob("github-project/*.json")):
        board = json.loads(path.read_text(encoding="utf-8"))
        add(f"## Board: {board.get('title')} ({board.get('totalCount')} items)")
        add("")
        add(f"<{board.get('url')}> -- `{path.relative_to(HERE)}`")
        add("")
        for group in board.get("groups", []):
            add(f"### {group.get('group') or 'No status'} ({len(group['items'])})")
            add("")
            for it in group["items"]:
                ref = f"{it.get('repository')}#{it.get('number')}"
                add(f"- [{ref}]({it.get('url')}) -- {it.get('title')} ({it.get('state')})")
            add("")

    pads = sorted(RAW.glob("hedgedoc/*.md"))
    if pads:
        add(f"## Pads ({len(pads)})")
        add("")
        for path in pads:
            src = next(
                (s for s in manifest["sources"] if s["id"] == path.stem),
                {},
            )
            add(f"- [`{path.relative_to(HERE)}`]({path.name}) -- <{src.get('url', '')}>")
        add("")

    add("## Sources")
    add("")
    add("| id | kind | what it reaches | why |")
    add("| --- | --- | --- | --- |")
    for s in manifest["sources"]:
        reach = {
            "github-item": lambda s: f"`{s['ref']}`",
            "github-query": lambda s: f"`{s['q']}`",
            "github-project": lambda s: f"orgs/{s['org']}/projects/{s['number']}",
            "discourse-topic": lambda s: f"{s['host']}/t/{s['topic']}",
            "discourse-query": lambda s: f"`{s['q']}` on {s['host']}",
            "hedgedoc": lambda s: s["url"],
        }.get(s["kind"], lambda s: "")(s)
        note = " (recorded, not fetched)" if s.get("expand") is False else ""
        add(f"| `{s['id']}` | {s['kind']}{note} | {reach} | {why[s['id']]} |")
    add("")

    if manifest.get("unfetched"):
        add("## Deliberately not fetched")
        add("")
        for u in manifest["unfetched"]:
            add(f"- **{u['what']}** -- <{u['url']}>  ")
            add(f"  {u['why']}")
        add("")

    write_text(HERE / "INDEX.md", "\n".join(lines), check)


# ---------------------------------------------------------------------------
# the run
# ---------------------------------------------------------------------------


def matches(entry_title: str, source: dict) -> bool:
    keep = source.get("match")
    drop = source.get("exclude")
    if keep and not re.search(keep, entry_title, re.I):
        return False
    if drop and re.search(drop, entry_title, re.I):
        return False
    return True


def run(args) -> int:
    manifest = json.loads((HERE / "sources.json").read_text(encoding="utf-8"))
    sources = manifest["sources"]
    if args.only:
        wanted = set(args.only)
        sources = [s for s in sources if s["id"] in wanted]
        if not sources:
            print(f"no source matches {args.only}", file=sys.stderr)
            return 2

    # ETags from the last run. `--no-prune` writes a differently shaped corpus,
    # so a 304 against a pruned file would be wrong; the cache is bypassed there.
    etag_path = STATE / "etags.json"
    etags = {}
    if etag_path.exists() and not (args.no_prune or args.force):
        etags = json.loads(etag_path.read_text(encoding="utf-8")).get("etags", {})
    f = Fetcher(verbose=args.verbose, etags=etags)
    report = Report()
    links: dict[str, int] = {}
    # Every item any query resolved to, with the query ids that reached it: the
    # answer to "why is this in the corpus?", which a bare file tree cannot give.
    provenance: dict[str, list[str]] = {}
    query_results: dict[str, list] = {}
    tracked_items: list[str] = []

    def note(source_id: str, ref: str) -> None:
        provenance.setdefault(ref, [])
        if source_id not in provenance[ref]:
            provenance[ref].append(source_id)

    # Pass 1: resolve every source to the concrete things it names.
    for s in sources:
        kind, sid = s["kind"], s["id"]
        if kind == "github-item":
            note(sid, s["ref"])
            tracked_items.append(s["ref"])
        elif kind == "github-query":
            print(f"[query] {sid}: {s['q']}", file=sys.stderr)
            try:
                # One reservation per query. `--paginate` can spend more than
                # one search request on a query with over 100 hits; none does
                # today, and the pacing has 2 of 30 in hand for the day one
                # might.
                f.pace_search()
                q = urllib.parse.quote(s["q"], safe="")
                hits = f.gh(f"search/issues?q={q}&per_page=100", paginate=True) or []
            except RuntimeError as e:
                report.errors.append(f"{sid}: {e}")
                continue
            rows = []
            for h in hits:
                repo_full = h["repository_url"].split("/repos/", 1)[1]
                ref = f"{repo_full}#{h['number']}"
                row = {
                    "ref": ref,
                    "title": h["title"],
                    "state": h["state"],
                    "comments": h["comments"],
                    "updated_at": h["updated_at"],
                    "kept": matches(h["title"], s),
                }
                rows.append(row)
                if row["kept"] and s.get("expand", True):
                    note(sid, ref)
                    tracked_items.append(ref)
            query_results[sid] = rows
            print(
                f"        {len(rows)} hits, {sum(1 for r in rows if r['kept'])} kept",
                file=sys.stderr,
            )
        elif kind == "discourse-query":
            print(f"[query] {sid}: {s['q']}", file=sys.stderr)
            host = s["host"]
            q = urllib.parse.quote(s["q"], safe="")
            data = f.http(f"https://{host}/search.json?q={q}") or {}
            rows = []
            for t in data.get("topics", []):
                row = {
                    "id": t["id"],
                    "title": t["title"],
                    "posts_count": t["posts_count"],
                    "kept": matches(t["title"], s),
                }
                rows.append(row)
                if row["kept"] and s.get("expand", True):
                    note(sid, f"discourse:{host}/t/{t['id']}")
            query_results[sid] = rows
            print(
                f"        {len(rows)} hits, {sum(1 for r in rows if r['kept'])} kept",
                file=sys.stderr,
            )
        elif kind == "discourse-topic":
            note(sid, f"discourse:{s['host']}/t/{s['topic']}")
        elif kind in ("github-project", "hedgedoc"):
            pass  # fetched in pass 3; they resolve to nothing first.
        else:
            # `checks.crowdsource-manifest` rejects this at eval time, so
            # reaching it means the manifest was edited without one.
            report.errors.append(f"{sid}: unknown kind '{kind}'")

    # Pass 2: fetch. Deduplicated, because a thread reached by three queries is
    # still one thread.
    seen_items = []
    for ref in tracked_items:
        if ref not in seen_items:
            seen_items.append(ref)

    for ref in seen_items:
        m = ITEM_RE.match(ref)
        if not m:
            report.errors.append(f"unparseable item ref: {ref}")
            continue
        path = item_path(m["owner"], m["repo"], int(m["number"]))
        existing = None
        if path.exists() and not args.no_prune:
            try:
                existing = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                existing = None
        try:
            record, _ = fetch_github_item(
                f, ref, prune_on=not args.no_prune, existing=existing
            )
        except RuntimeError as e:
            report.errors.append(f"{ref}: {e}")
            continue
        if record is None:
            report.errors.append(f"{ref}: not found or not readable")
            continue
        # Under `--only` the run has seen a fraction of the manifest, so what
        # it knows about provenance is a fraction too. Merging rather than
        # replacing keeps it from writing that fraction into the record as if
        # it were the whole answer.
        reached = set(provenance.get(ref, []))
        if args.only and existing:
            reached |= set(existing.get("sources", []))
        # Sorted, not in manifest order: reordering sources.json is then not a
        # reason for every record in the corpus to change.
        record["sources"] = sorted(reached)
        harvest_links("\n".join(texts(record)), links)
        state = write_json(path, record, args.check)
        label = f"{ref} — {record['issue'].get('title', '')[:70]}"
        if state == "new":
            report.new.append(label)
        elif state == "updated":
            report.updated.append(label)
        else:
            report.unchanged += 1

    for ref in [r for r in provenance if r.startswith("discourse:")]:
        host, _, topic = ref[len("discourse:") :].partition("/t/")
        record = fetch_discourse_topic(f, host, int(topic))
        if record is None:
            report.errors.append(f"{ref}: not found")
            continue
        record["sources"] = sorted(provenance[ref])
        harvest_links("\n".join(texts(record)), links)
        state = write_json(RAW / "discourse" / host / f"{topic}.json", record, args.check)
        label = f"{ref} — {record.get('title', '')[:70]}"
        if state == "new":
            report.new.append(label)
        elif state == "updated":
            report.updated.append(label)
        else:
            report.unchanged += 1

    for s in sources:
        if s["kind"] == "hedgedoc":
            text = fetch_hedgedoc(f, s["url"])
            if text is NOT_MODIFIED:
                report.unchanged += 1
                continue
            if text is None:
                report.errors.append(f"{s['id']}: {s['url']} not readable")
                continue
            harvest_links(text, links)
            state = write_text(RAW / "hedgedoc" / f"{s['id']}.md", text, args.check)
            label = f"{s['id']} — {s['url']}"
            if state == "new":
                report.new.append(label)
            elif state == "updated":
                report.updated.append(label)
            else:
                report.unchanged += 1
        elif s["kind"] == "github-project":
            record = fetch_github_project(f, s["org"], s["number"])
            if record is None:
                report.errors.append(f"{s['id']}: board not readable")
                continue
            harvest_links("\n".join(texts(record)), links)
            for group in record["groups"]:
                for it in group["items"]:
                    if it.get("url"):
                        harvest_links(it["url"], links)
            state = write_json(
                RAW / "github-project" / f"{s['org']}-{s['number']}.json", record, args.check
            )
            label = f"{s['id']} — {record.get('title')}"
            if state == "new":
                report.new.append(label)
            elif state == "updated":
                report.updated.append(label)
            else:
                report.unchanged += 1

    # Pass 3: reconcile the corpus with the manifest, and describe it.
    #
    # `--only` has seen a fraction of the manifest, so everything here would be
    # wrong from it: it would delete every file its subset did not name, and
    # rewrite the state files to describe that subset as the whole. Validators
    # are the exception -- they are per resource, and a fresher one is never
    # wrong.
    tracked = set(seen_items) | set(provenance)
    if not args.check:
        write_json(STATE / "etags.json", {"etags": dict(sorted(f.etags.items()))}, False)
    if args.only:
        print("\n--only: no removals, and state files and INDEX.md left alone")
        report_run(report, f, {})
        return 0

    # What the manifest no longer reaches has to go: an `exclude` added to a
    # query, or a root removed, takes its files with it. A corpus that only ever
    # grows stops describing the manifest that supposedly produced it.
    for path in sorted(RAW.glob("github/*/*/*.json")):
        owner, repo = path.parent.parent.name, path.parent.name
        if f"{owner}/{repo}#{path.stem}" not in tracked:
            report.removed.append(f"{owner}/{repo}#{path.stem}")
            if not args.check:
                path.unlink()
    for path in sorted(RAW.glob("discourse/*/*.json")):
        if f"discourse:{path.parent.name}/t/{path.stem}" not in tracked:
            report.removed.append(f"discourse:{path.parent.name}/t/{path.stem}")
            if not args.check:
                path.unlink()

    discovered = {
        k: v
        for k, v in sorted(links.items(), key=lambda kv: (-kv[1], kv[0]))
        if k not in tracked and not is_ignored(manifest, k)
    }

    write_json(
        STATE / "queries.json",
        {qid: query_results[qid] for qid in sorted(query_results)},
        args.check,
    )
    write_json(
        STATE / "provenance.json",
        {ref: sorted(provenance[ref]) for ref in sorted(provenance)},
        args.check,
    )
    # A list rather than a mapping: the order *is* the information, and JSON
    # object keys get sorted on the way out.
    write_json(
        STATE / "discovered.json",
        {
            "note": (
                "Links seen in the fetched material that no source in "
                "sources.json tracks, most-mentioned first. Promote what "
                "belongs into sources.json; add the rest to `ignore`."
            ),
            "found": [{"ref": k, "mentions": v} for k, v in discovered.items()],
        },
        args.check,
    )

    if not args.check:
        write_index(manifest, args.check)

    report_run(report, f, discovered)
    if args.check and (report.new or report.updated or report.removed):
        return 1
    return 0


def report_run(report: Report, f: Fetcher, discovered: dict) -> None:
    print()
    if report.new:
        print(f"new ({len(report.new)}):")
        for x in report.new:
            print(f"  + {x}")
    if report.updated:
        print(f"changed ({len(report.updated)}):")
        for x in report.updated:
            print(f"  ~ {x}")
    if report.removed:
        print(f"no longer tracked ({len(report.removed)}):")
        for x in report.removed:
            print(f"  - {x}")
    print(
        f"unchanged: {report.unchanged}   requests: {f.requests} "
        f"({f.counted} counted against the rate limit, {f.not_modified} answered 304)"
    )
    if f.rate_remaining is not None:
        print(f"rate limit: {f.rate_remaining} of 5000 core requests left this hour")
    if discovered:
        top = list(discovered.items())[:15]
        print(f"untracked links seen ({len(discovered)}), most-mentioned first:")
        for k, v in top:
            print(f"  ? {k}  ({v})")
        print("  -> state/discovered.json for the full list")
    if report.errors:
        print(f"errors ({len(report.errors)}):")
        for e in report.errors:
            print(f"  ! {e}")


def is_ignored(manifest: dict, key: str) -> bool:
    for pattern in manifest.get("ignore", []):
        if re.search(pattern, key):
            return True
    return False


def main() -> int:
    # `prog` is set because the Nix wrapper runs this from the store, and a
    # usage line beginning with a hash helps nobody.
    p = argparse.ArgumentParser(
        prog="crowdsource-sync",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--check", action="store_true", help="write nothing; exit 1 if a run would")
    p.add_argument("--only", nargs="+", metavar="ID", help="only these source ids")
    p.add_argument("--no-prune", action="store_true", help="keep every API field")
    p.add_argument(
        "--force", action="store_true", help="ignore stored ETags; refetch everything"
    )
    p.add_argument("-v", "--verbose", action="store_true", help="log every request")
    p.add_argument(
        "--dir",
        type=Path,
        help="the crowdsource directory to read and write (default: this script's own)",
    )
    args = p.parse_args()
    if args.dir:
        set_dir(args.dir)
    if not (HERE / "sources.json").exists():
        print(f"no sources.json in {HERE}", file=sys.stderr)
        return 2
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
