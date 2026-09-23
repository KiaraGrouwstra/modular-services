# The nix-darwin integration's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
#
# TODO: add a test that runs the services on macOS. This needs a Darwin
# builder, and a test driver for it.
{
  lib,
  inputs,
  self,
  pkgs,
  ...
}:

let
  darwinLib = import ../lib.nix {
    inherit
      lib
      inputs
      self
      pkgs
      ;
  };

  eval = drv: {
    kind = "eval";
    inherit drv;
  };
in
{
  # The launchd daemons and `/etc` files that each variant makes.
  variants = eval (
    import ./variants.nix {
      inherit lib pkgs;
      inherit (darwinLib) evalSystem;
    }
  );
}
