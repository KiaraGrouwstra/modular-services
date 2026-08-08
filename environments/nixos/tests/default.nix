# The NixOS environment's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
#
# `kind` splits the CI matrix: `"eval"` tests build without a VM, `"vm"` tests
# need `/dev/kvm`. `ci/tests.nix` prefixes each name with the environment name,
# so `disable-proof` here becomes `checks.nixos-disable-proof`.
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

  inherit (nixosLib) evalModules evalSystem;

  eval = drv: {
    kind = "eval";
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
}
