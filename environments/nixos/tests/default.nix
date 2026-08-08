# The NixOS environment's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
#
# `kind` splits the CI matrix: `"eval"` tests build without a VM, `"vm"` tests
# need `/dev/kvm`. `ci/tests.nix` prefixes each name with the environment name,
# so `units` here becomes `checks.nixos-units`.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  nixosLib = import ../lib.nix {
    inherit
      lib
      nixpkgs
      self
      pkgs
      ;
  };

  inherit (nixosLib) evalModules evalSystem runTest;

  compliance = import ./compliance.nix {
    inherit
      pkgs
      self
      evalSystem
      runTest
      ;
  };

  eval = drv: {
    kind = "eval";
    inherit drv;
  };
  vm = drv: {
    kind = "vm";
    inherit drv;
  };
in

{
  # The crux: proof that the upstream copy is gone and ours is in its place.
  disable-proof = eval (
    import ./disable-proof.nix {
      inherit
        lib
        self
        pkgs
        evalModules
        evalSystem
        ;
    }
  );

  # Rendered systemd units for a representative service tree.
  units = eval (pkgs.callPackage ./units.nix { inherit evalSystem; });
}
// lib.mapAttrs' (name: value: {
  name = "compliance-${name}";
  value = if lib.hasSuffix "eval" name then eval value else vm value;
}) compliance
