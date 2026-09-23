# The devenv integration's test set.
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
  devenvLib = import ../lib.nix {
    inherit
      lib
      inputs
      self
      pkgs
      ;
  };

  inherit (devenvLib) evalSystem runTest;

  eval = drv: {
    kind = "eval";
    inherit drv;
  };
in
{
  # The processes that each variant makes.
  variants = eval (import ./variants.nix { inherit lib pkgs evalSystem; });

  # No virtual machine: the processes run in the build sandbox.
  pkg-postgresql = eval (runTest (import ./packages/postgresql.nix));
}
