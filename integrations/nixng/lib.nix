# How to evaluate and test modular services in the NixNG integration.
{
  lib,
  inputs,
  self,
  pkgs,
}:

let
  nglib = import (inputs.nixng + "/lib") lib;
in
{
  /**
    Evaluate a NixNG system with this repo's modular services. As
    `makeSystem` in NixNG's `lib/make-system.nix` does, this imports all NixNG
    modules. It uses `pkgs` with NixNG's overlay, in place of a second
    nixpkgs, as `makeSystem` needs the nixpkgs source with `.lib`. It does not
    check the assertions.
  */
  evalSystem =
    module:
    lib.evalModules {
      specialArgs = { inherit nglib; };
      modules = import (inputs.nixng + "/modules/list.nix") ++ [
        (pkgs.path + "/nixos/modules/misc/nixpkgs.nix")
        {
          disabledModules = [ (pkgs.path + "/nixos/modules/misc/assertions.nix") ];
          nixpkgs.pkgs = pkgs.extend (import (inputs.nixng + "/overlay"));
          _module.args.system = pkgs.stdenv.hostPlatform.system;
          networking.hostName = "machine";
          system.name = "machine";
        }
        self.nixngModules.default
        module
      ];
    };
}
