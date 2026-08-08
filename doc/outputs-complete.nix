# Every output must be described, and every description must name an output.
#
# `doc/outputs.nix` is what the manual's "Flake attributes" chapter renders, so
# without this an output could arrive undocumented, or a removed one could go on
# being documented, and the chapter would look just as complete either way.
#
# Only attribute names are read, never a value. `checks.docs` is the manual, and
# the manual reads `doc/outputs.nix`, so forcing one would be circular.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  inherit (import ./outputs.nix) fixed generated;

  # Called the way `ci/non-flake.nix` calls it: this is the surface a consumer
  # sees, which is the surface being described.
  base = import ../. { inherit lib nixpkgs pkgs; };

  topLevel = path: lib.head (lib.splitString "." path);

  paths = lib.attrNames fixed;

  childrenOf = name: map (lib.removePrefix "${name}.") (lib.filter (lib.hasPrefix "${name}.") paths);

  declared = lib.unique (map topLevel paths ++ lib.attrNames generated);
  provided = lib.attrNames base;

  # Only the attributes written as `<name>.<child>` have their members
  # described one by one; `generated` names the sets the chapter lists instead,
  # and a name with no `.` is an output that is not an attribute set. A name
  # that is not produced at all is left to the top-level comparison, so that it
  # is reported rather than thrown over.
  described = lib.filter (name: childrenOf name != [ ] && base ? ${name}) declared;

  drift =
    name: inTable: inReality:
    let
      undescribed = lib.subtractLists inTable inReality;
      stale = lib.subtractLists inReality inTable;
    in
    lib.optional (undescribed != [ ]) "${name}: produced but not described: ${toString undescribed}"
    ++ lib.optional (stale != [ ]) "${name}: described but not produced: ${toString stale}";

  problems =
    drift "default.nix" declared provided
    ++ lib.concatMap (name: drift name (childrenOf name) (lib.attrNames base.${name})) described;
in

assert lib.assertMsg (problems == [ ]) ''
  docs-outputs-complete: doc/outputs.nix and the outputs have drifted apart:

  ${lib.concatMapStringsSep "\n" (p: "  - ${p}") problems}
'';

pkgs.runCommand "docs-outputs-complete" { } ''
  echo 'described outputs:'
  ${lib.concatMapStringsSep "\n" (p: "echo '  - ${p}'") (
    lib.sort (a: b: a < b) (paths ++ lib.attrNames generated)
  )}
  touch $out
''
