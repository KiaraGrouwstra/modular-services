# The finix integration's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
{
  lib,
  inputs,
  self,
  pkgs,
  ...
}:

let
  finixLib = import ../lib.nix {
    inherit
      lib
      inputs
      self
      pkgs
      ;
  };

  inherit (finixLib) evalSystem runTest;

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
  # The finit services and `/etc` files that each variant makes.
  variants = eval (import ./variants.nix { inherit lib pkgs evalSystem; });

  pkg-postgresql = vm (runTest (import ./packages/postgresql.nix));
}
