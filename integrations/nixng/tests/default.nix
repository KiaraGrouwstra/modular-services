# The NixNG integration's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
#
# TODO: NixNG has no test driver. Add a test that runs the services, for
# example in a container from `system.build.ociImage`.
{
  lib,
  inputs,
  self,
  pkgs,
  ...
}:

let
  nixngLib = import ../lib.nix {
    inherit
      lib
      inputs
      self
      pkgs
      ;
  };

  inherit (nixngLib) evalSystem;

  eval = drv: {
    kind = "eval";
    inherit drv;
  };
in
{
  # The init services and `/etc` files that each variant makes, for each
  # init system.
  variants-dinit = eval (
    import ./variants.nix {
      inherit lib pkgs evalSystem;
      initSystem = "dinit";
    }
  );
  variants-runit = eval (
    import ./variants.nix {
      inherit lib pkgs evalSystem;
      initSystem = "runit";
    }
  );
}
