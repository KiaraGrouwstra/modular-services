# The NixBSD integration's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
#
# TODO: add a test that runs the services in a FreeBSD VM. This needs a
# FreeBSD test driver, and a cross-compiled FreeBSD system.
{
  lib,
  inputs,
  self,
  pkgs,
  ...
}:

let
  nixbsdLib = import ../lib.nix {
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
  # The rc services and `/etc` files that each variant makes.
  variants = eval (
    import ./variants.nix {
      inherit lib pkgs;
      inherit (nixbsdLib) evalSystem;
    }
  );
}
