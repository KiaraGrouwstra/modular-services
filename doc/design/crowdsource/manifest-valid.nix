# `sources.json` says what it must, and says it once.
#
# The manifest is edited by hand and read by a Python script that runs for
# twenty minutes against four APIs. A typo in a `kind` there surfaces as a
# source that is quietly never fetched, which is exactly the failure this
# directory exists to prevent -- a knowledge base with a hole in it looks the
# same as one without.
#
# Evaluating it here catches that at `nix flake check`, before anyone waits for
# a sync. Only the shape is checked: whether a query still matches anything is a
# question for the network, and `state/queries.json` answers it after each run.
{
  lib,
  pkgs,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./sources.json);

  # Each kind, and the fields it cannot do without. `why` is required of every
  # source: an entry nobody justified is an entry nobody can decide to remove.
  required = {
    github-item = [ "ref" ];
    github-query = [ "q" ];
    github-project = [
      "org"
      "number"
    ];
    discourse-topic = [
      "host"
      "topic"
    ];
    discourse-query = [
      "host"
      "q"
    ];
    hedgedoc = [ "url" ];
    matrix-room = [ "room" ];
  };

  ids = map (s: s.id) manifest.sources;

  duplicated = lib.subtractLists (lib.unique ids) ids;

  problems =
    lib.optional (duplicated != [ ]) "duplicate source ids: ${toString duplicated}"
    ++ lib.concatMap (
      s:
      let
        at = "source '${s.id or "<no id>"}'";
      in
      lib.optional (!(s ? id)) "a source has no id: ${builtins.toJSON s}"
      ++ lib.optional (!(s ? kind)) "${at}: no kind"
      ++ lib.optional (
        s ? kind && !(required ? ${s.kind})
      ) "${at}: unknown kind '${s.kind}', expected one of ${toString (lib.attrNames required)}"
      ++ lib.optional (
        (s.why or "") == ""
      ) "${at}: no `why`. Say what it settles or leaves open, in a sentence."
      ++ lib.optional (
        s ? kind && required ? ${s.kind} && lib.any (f: !(s ? ${f})) required.${s.kind}
      ) "${at}: kind '${s.kind}' needs ${toString required.${s.kind}}"
      # A GitHub issue search is rejected outright without one of these, and the
      # error arrives 20 queries into a run.
      ++ lib.optional (
        s.kind or "" == "github-query"
        && !(lib.hasInfix "is:issue" s.q || lib.hasInfix "is:pull-request" s.q)
      ) "${at}: a github-query needs `is:issue` or `is:pull-request`; the API refuses it otherwise"
    ) manifest.sources;
in

assert lib.assertMsg (problems == [ ]) ''
  crowdsource-manifest: doc/design/crowdsource/sources.json is malformed:

  ${lib.concatMapStringsSep "\n" (p: "  - ${p}") problems}
'';

pkgs.runCommand "crowdsource-manifest" { } ''
  echo '${toString (lib.length manifest.sources)} sources, all well-formed'
  touch $out
''
