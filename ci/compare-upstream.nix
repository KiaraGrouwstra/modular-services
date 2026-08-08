# Diff every vendored file against the pinned nixpkgs.
#
# The file list is parsed out of ../PROVENANCE.md, so that table is the single
# source of truth and cannot silently go stale: a row naming a path that no
# longer exists on either side fails the check.
#
# Rows marked `verbatim` must be byte-identical; a difference fails.
# Rows marked `modified` are expected to differ; their diff is printed as
# context so upstream churn stays visible.
#
# CI runs this with `continue-on-error: true`: cosmetic churn upstream should be
# visible, but must not red-flag an unrelated pull request.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  provenance = builtins.readFile ../PROVENANCE.md;

  # `| a | b | c | d | e |` -> [ "a" "b" "c" "d" "e" ]
  parseRow =
    line:
    let
      cells = lib.splitString "|" line;
      trimmed = map (c: lib.replaceStrings [ "`" ] [ "" ] (lib.trim c)) cells;
      # A leading and a trailing empty cell come from the outer pipes.
      inner = lib.sublist 1 (lib.length trimmed - 2) trimmed;
    in
    inner;

  isSeparator =
    cells:
    lib.all (c: c == "" || lib.all (ch: ch == "-" || ch == ":") (lib.stringToCharacters c)) cells;

  rows =
    let
      lines = lib.filter (l: lib.hasPrefix "|" (lib.trim l)) (lib.splitString "\n" provenance);
      parsed = map parseRow lines;
      dataRows = lib.filter (
        cells: (lib.length cells == 4) && !isSeparator cells && (lib.elemAt cells 0 != "repo path")
      ) parsed;
    in
    map (cells: {
      repoPath = lib.elemAt cells 0;
      nixpkgsPath = lib.elemAt cells 1;
      state = lib.elemAt cells 2;
      reason = lib.elemAt cells 3;
    }) dataRows;

  badState = lib.filter (
    r:
    !(lib.elem r.state [
      "verbatim"
      "modified"
    ])
  ) rows;

  missingLocally = lib.filter (r: !builtins.pathExists ("${self}/" + r.repoPath)) rows;
in

assert lib.assertMsg (rows != [ ]) ''
  upstream-drift: parsed no rows out of PROVENANCE.md. The provenance table
  must have four columns: repo path | nixpkgs path | verbatim/modified | reason.
'';

assert lib.assertMsg (badState == [ ]) ''
  upstream-drift: PROVENANCE.md rows with an unrecognised state column
  (expected `verbatim` or `modified`):

  ${lib.concatMapStringsSep "\n" (r: "  - ${r.repoPath}: ${r.state}") badState}
'';

assert lib.assertMsg (missingLocally == [ ]) ''
  upstream-drift: PROVENANCE.md names files that do not exist in this repo:

  ${lib.concatMapStringsSep "\n" (r: "  - ${r.repoPath}") missingLocally}
'';

pkgs.runCommand "upstream-drift"
  {
    nativeBuildInputs = [ pkgs.diffutils ];
    passthru = { inherit rows; };
  }
  ''
    status=0
    missing=0

    check() {
      local state="$1" repoPath="$2" upstreamPath="$3"
      local ours="${self}/$repoPath"
      local theirs="${nixpkgs}/$upstreamPath"

      if [[ ! -e "$theirs" ]]; then
        echo "GONE      $upstreamPath (referenced by $repoPath)" >&2
        missing=1
        return
      fi

      if diff -u "$theirs" "$ours" > "$TMPDIR/d"; then
        echo "SAME      $repoPath"
      elif [[ "$state" == verbatim ]]; then
        echo "DRIFTED   $repoPath vs $upstreamPath" >&2
        sed 's/^/    /' "$TMPDIR/d" >&2
        status=1
      else
        echo "MODIFIED  $repoPath vs $upstreamPath (expected to differ)"
        sed 's/^/    /' "$TMPDIR/d"
      fi
    }

    ${lib.concatMapStringsSep "\n" (
      r:
      "check ${
        lib.escapeShellArgs [
          r.state
          r.repoPath
          r.nixpkgsPath
        ]
      }"
    ) rows}

    if [[ $missing == 1 ]]; then
      echo "" >&2
      echo "Some files listed in PROVENANCE.md no longer exist in the pinned nixpkgs." >&2
      echo "Update the table, and check whether environments/nixos/disable-upstream.nix" >&2
      echo "still names the right modules." >&2
      status=1
    fi

    if [[ $status == 1 ]]; then
      echo "" >&2
      echo "A file marked \`verbatim\` differs from upstream. Either re-vendor it," >&2
      echo "or record the divergence by marking the row \`modified\` with a reason." >&2
      exit 1
    fi

    touch $out
  ''
