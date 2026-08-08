# Every entry of `modularServices` must be documented, and every documented
# entry must exist.
{
  lib,
  self,
  pkgs,
}:

let
  inherit (self) modularServices;

  registry = import ./registry.nix;

  provided = lib.attrNames modularServices;

  undocumented = lib.subtractLists registry provided;
  unknown = lib.subtractLists provided registry;
in

assert lib.assertMsg (undocumented == [ ]) ''
  docs-registry-complete: service modules missing from doc/registry.nix:

  ${lib.concatMapStringsSep "\n" (n: "  - ${n}") undocumented}
'';

assert lib.assertMsg (unknown == [ ]) ''
  docs-registry-complete: doc/registry.nix lists names that are not in
  modular-services/default.nix:

  ${lib.concatMapStringsSep "\n" (n: "  - ${n}") unknown}
'';

pkgs.runCommand "docs-registry-complete" { } ''
  echo "documented service modules:"
  ${lib.concatMapStringsSep "\n" (n: "echo '  - ${n}'") registry}
  touch $out
''
