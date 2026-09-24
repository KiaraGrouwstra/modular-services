# How to evaluate modular services in the nix-darwin integration.
{
  lib,
  inputs,
  self,
  pkgs,
}:

{
  /**
    Evaluate a nix-darwin system for `aarch64-darwin` with this repo's modular
    services. As in nix-darwin's flake, this uses `eval-config.nix`, with the
    nixpkgs of `pkgs`.
  */
  evalSystem =
    module:
    import (inputs.nix-darwin + "/eval-config.nix") {
      inherit lib;
      modules = [
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          nixpkgs.source = pkgs.path;
          system.stateVersion = 6;
        }
        self.darwinModules.default
        module
      ];
    };
}
