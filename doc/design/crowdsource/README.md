# The crowdsourced design record

The design of modular services is not written down in one place. It is spread
across a merged nixpkgs pull request, a closed RFC, a tracking issue, the
minutes of every meeting so far, three integrations in three repositories, and
a Matrix channel. Reading it takes a day and reading it *again* -- next month, or from
another machine, or by an agent that has no browser -- takes another day.

This directory is that reading, fetched and committed. `raw/` holds the
discussions as the APIs return them, [`INDEX.md`](./INDEX.md) is the same corpus
with titles and reasons attached, and [`sync.py`](./sync.py) refreshes both.

It is a record, not an argument: nothing here is anybody's summary of what the
design should be. Work that draws conclusions belongs in `doc/design/` beside
it, citing files in here.

## Why the raw material is committed

Because the point is to be able to *grep* it, and to see what moved. A tool that
fetched on demand would answer a question and forget it; a checked-in corpus
gives every later reader the same bytes, works offline, and turns "what has the
discussion done since we last looked" into `git diff`.

Nothing in `raw/` is vendored the way [`PROVENANCE.md`](../../../PROVENANCE.md)
means it: no code from it is built, imported or shipped. It is a cache of public
discussion, every entry carrying its author and a link back to where they wrote
it, and it stays that way -- an argument quoted out of here belongs beside its
link, not in place of it.

## Layout

| path | what |
| --- | --- |
| [`sources.json`](./sources.json) | The manifest: every source, and why it is one. The only file to edit by hand. |
| [`sync.py`](./sync.py) | Fetches everything the manifest names, writes `raw/`, `state/` and `INDEX.md`. |
| [`INDEX.md`](./INDEX.md) | Generated. Every item with title, state, activity and the manifest entries that reached it. |
| `raw/github/<owner>/<repo>/<n>.json` | One issue or pull request: body, comments, reviews, review comments, and the timeline events that point elsewhere. |
| `raw/discourse/<host>/<n>.json` | One Discourse topic, every post, Markdown source rather than rendered HTML. |
| `raw/github-project/<org>-<n>.json` | The project board: items grouped by status, which no issue query recovers. |
| `raw/hedgedoc/<id>.md` | A pad, as Markdown. |
| `state/queries.json` | What each search matched last run, kept or filtered. |
| `state/provenance.json` | Which manifest entries reached each item. |
| `state/discovered.json` | Links the corpus mentions that nothing tracks yet. The triage queue. |
| `state/etags.json` | Response validators, so a refresh costs almost no rate limit. |

## Refreshing it

```console
$ nix run .#crowdsource-sync          # fetch, write, report
$ nix run .#crowdsource-sync -- --check   # report only; exit 1 if stale
```

Without Nix, `python3 doc/design/crowdsource/sync.py` does the same; it needs
`gh` authenticated and nothing else.

A run prints what is new, what changed, and which untracked links came up. The
files it writes are the rest of the report: `git diff` after a sync shows every
comment the world added, in place.

`--check` writes nothing and exits 1 when a real run would change something,
which is what the scheduled workflow in
[`.github/workflows/crowdsource.yml`](../../../.github/workflows/crowdsource.yml)
uses to decide whether there is a pull request to open.

Other flags: `--only <id>...` for one source, `--force` to ignore the validator
cache, `--no-prune` to keep every API field, `-v` to log each request.

## What "tracked" means, and what it does not

The manifest holds two kinds of entry.

**Roots** are named outright: an issue, a topic, a board, a pad. They are here
because somebody decided they belong, and the `why` field says what that person
was thinking.

**Queries** are the part that keeps working without anyone's attention. A
scoped GitHub or Discourse search runs each sync and everything it matches is
fetched, so meeting #8, or the next issue somebody labels, arrives on its own.
This is what stops the corpus from being a snapshot of one afternoon. A query
may carry `match`/`exclude` regexes over the title, and `"expand": false` for a
list worth watching but too large to carry -- those land in `state/queries.json`
and are never fetched.

What the manifest deliberately does *not* do is crawl. One nixpkgs thread links
half of nixpkgs, and a crawl depth is a number nobody can defend. Instead every
link the corpus mentions is counted and, if untracked, written to
`state/discovered.json` most-mentioned first. Promoting a line of that file into
`sources.json` is how the record grows, and it stays a judgement somebody made.
Recurring noise goes in `ignore` with a note saying what it was.

Only human-written fields are harvested for those links -- a `diff_hunk` repeats
the surrounding patch on every review comment, and a URL that happens to sit in
a nearby source line would otherwise outrank the links people actually posted.

## Rate limits

GitHub allows 5000 core requests an hour and **30 searches a minute**; the
searches are the tighter of the two, and `sync.py` paces itself under them.

A full fetch is around 950 requests. A refresh where nothing moved is about 240,
of which fewer than 30 count against the limit, because every item is gated
behind one conditional request: the ETag of
the last response is replayed as `If-None-Match`, and GitHub answers 304 without
counting it against the limit.

The gate is `issues/{n}`, for pull requests too. A pull request is an issue
underneath, and both endpoints report the same `updated_at` -- moved by a
comment, an edit, a review, a review comment, a label or a state change alike --
so one 304 is reason enough not to ask for the six list endpoints behind it.

Gating on `pulls/{n}` as well was the first attempt and was worse than useless:
that payload embeds the repository object, live star and fork counts included,
and on nixpkgs those move every few minutes and take the ETag with them. It
refetched a hundred pull requests a run to write byte-identical files.

`--force` declines the whole arrangement.

Discourse and the project board send `cache-control: no-store` and no validator,
so they are fetched unconditionally every time. That is most of what a quiet
refresh still spends, and it is against nobody's quota.

## What is pruned, and why

`raw/` holds the API response minus a fixed list of keys that carry no
discussion: the `*_url` fields that are derivable from the ids beside them,
`node_id`, avatar URLs, the `body_html`/`cooked` renderings of a body kept
verbatim anyway, and the viewer-dependent flags Discourse attaches to every
post. That is roughly two thirds of the bytes.

The saving is not the point. Keeping the diff between two syncs *readable* is,
and two of the rules exist only for that:

A pull request carries the whole repository object three times over, and that
object holds nixpkgs' live star, fork and open-issue counts. Left in, every
refresh rewrote a hundred files with numbers nobody asked about. A
repository-shaped dict is therefore reduced to what identifies it.

Discourse counts reads per post and views per topic. Both move because somebody
opened a page, so both are dropped.

What is left changes when a person writes something, which is what makes
`git diff` after a sync worth reading at all.

The timeline is kept only for what the rest of the record does not already say:
which commits and issues point at an item, what its title used to be, and when
it opened and closed. `commented` and `reviewed` events are dropped because they
restate `comments` and `reviews` in full -- 2113 times over 173 items, when they
were kept.

`--no-prune` turns all of it off. The prune list is at the top of `sync.py`.

Changing what is pruned changes the shape of every file, and a refresh will not
notice: an item whose ETag still matches is left exactly as it was. Follow such
a change with one `--force` run, which refetches the corpus against the new
rules.

## The gap

The Matrix channel `#modular-services:nixos.org` is where the day-to-day
conversation happens, and nothing here reads it: that needs an account and a
homeserver, and a checked-in sync tool should not carry credentials for one.
What is decided there is expected to reach the pad or an issue. If that stops
being true, this is the gap to close, and `sources.json` records it under
`unfetched` alongside the two proposal branches that have no thread to fetch.

## Adding a source

Add an entry to `sources.json` and run the sync. The `kind` decides the rest:

```json
{
  "id": "short-stable-name",
  "kind": "github-item",
  "ref": "NixOS/nixpkgs#428084",
  "why": "One or two sentences. Not what it is -- the title says that -- but what it settles or leaves open."
}
```

`kind` is one of `github-item`, `github-query`, `github-project`,
`discourse-topic`, `discourse-query` or `hedgedoc`. A source that needs a
seventh kind needs a function in `sync.py`; they are around forty lines each.

The `why` is not decoration. It is what tells the next reader -- or the next
agent -- whether an item is worth opening, and it is the only part of this
directory a machine cannot regenerate.
