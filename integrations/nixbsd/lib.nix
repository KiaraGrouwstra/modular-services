# How to evaluate modular services in the NixBSD integration.
{
  lib,
  inputs,
  self,
  pkgs,
}:

{
  /**
    Evaluate a NixBSD system for `x86_64-freebsd` with this repo's modular
    services, cross-compiled from the platform of `pkgs`. As in NixBSD's
    flake, this uses `lib/eval-config.nix` with the nixpkgs that NixBSD
    locks, `inputs.nixbsd-nixpkgs`.
  */
  evalSystem =
    module:
    import (inputs.nixbsd + "/lib/eval-config.nix") {
      lib = import (inputs.nixbsd-nixpkgs + "/lib");
      nixpkgsPath = inputs.nixbsd-nixpkgs;
      system = null;
      # NixBSD's flake gives its `cppnix` and `mini-tmpfiles` inputs here, for
      # overlays. Without `cppnix`, the system uses `nix` from nixpkgs. The
      # system needs `mini-tmpfiles`, which is not in nixpkgs.
      specialArgs = {
        cppnixFlake = null;
        # Only `overlays.default` is used, and it does not use the inputs of
        # the flake.
        mini-tmpfiles-flake = (import (inputs.nixbsd-mini-tmpfiles + "/flake.nix")).outputs {
          self = null;
          nixpkgs = null;
        };
      };
      modules = [
        {
          nixpkgs.hostPlatform = "x86_64-freebsd";
          nixpkgs.buildPlatform = pkgs.stdenv.buildPlatform.system;
          networking.hostName = "machine";
          # As in NixBSD's `configurations/base`. The system does not evaluate
          # without a root file system.
          boot.loader.stand-freebsd.enable = true;
          fileSystems."/" = {
            device = "/dev/gpt/nixos";
            fsType = "ufs";
          };
        }
        self.nixbsdModules.default
        module
      ];
    };
}
