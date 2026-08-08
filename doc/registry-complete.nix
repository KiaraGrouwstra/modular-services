# Every entry of `serviceModules` must be documented, and every documented
# entry must exist.
{
  lib,
  self,
  pkgs,
}:

let
  inherit (self) serviceModules;

  inherit (import ./service-modules.nix { inherit lib serviceModules; }) registry;

  provided = lib.attrNames serviceModules;

  undocumented = lib.subtractLists registry provided;
  unknown = lib.subtractLists provided registry;
in

assert lib.assertMsg (undocumented == [ ]) ''
  docs-registry-complete: service modules missing from doc/service-modules.nix:

  ${lib.concatMapStringsSep "\n" (n: "  - ${n}") undocumented}
'';

assert lib.assertMsg (unknown == [ ]) ''
  docs-registry-complete: doc/service-modules.nix lists names that are not in
  service-modules/default.nix:

  ${lib.concatMapStringsSep "\n" (n: "  - ${n}") unknown}
'';

pkgs.runCommand "docs-registry-complete" { } ''
  echo "documented service modules:"
  ${lib.concatMapStringsSep "\n" (n: "echo '  - ${n}'") registry}
  touch $out
''
