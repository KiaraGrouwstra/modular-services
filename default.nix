# Everything this repository offers a consumer, from a `lib` the caller supplies.
#
# This is the whole of the consumer surface, and `flake.nix` is a wrapper around
# it: the flake adds the pinned nixpkgs, the per-system `checks`, `packages`,
# `devShells` and `formatter`, and nothing else. Deriving one from the other is
# what keeps a non-flake consumer from getting a second-class subset.
#
# Nothing here evaluates this repository's own nixpkgs, and nothing here needs a
# flake to exist. The NixOS module takes `lib` and `pkgs` from the configuration
# importing it, and `disable-upstream.nix` names the module it removes by a key
# relative to that configuration's `modulesPath`. A consumer therefore never
# pulls in a second nixpkgs, whatever mechanism they used to fetch this source.
#
# ```nix
# # in a NixOS configuration, with `src` however you fetched this repository
# { pkgs, ... }:
# let
#   modular-services = import src { inherit (pkgs) lib; };
# in
# {
#   imports = [ modular-services.nixosModules.default ];
#   system.services.tlshd.imports = [ (modular-services.serviceModules.ktls-utils pkgs) ];
# }
# ```
{ lib }:

let
  serviceModules = import ./service-modules { inherit lib; };
in

{
  lib = {
    /**
      The portable layer, instantiated against a caller-supplied `lib`. This is
      the entry point for implementing a new environment; see the `configure`
      docstring in lib/services/default.nix.
    */
    servicesFor = lib': import ./lib/services { lib = lib'; };

    /**
      The portable layer, against the `lib` this file was called with.
    */
    services = import ./lib/services { inherit lib; };

    /**
      The environment-agnostic compliance suite, instantiated for a package set.
      See compliance/README.md for the arguments it takes.
    */
    mkComplianceSuite = pkgs: pkgs.callPackage ./compliance { };
  };

  /**
    The canonical way to consume a service: `serviceModules.<pkg> pkgs` yields a
    module to import into `system.services.<name>`.
  */
  inherit serviceModules;

  nixosModules = {
    # Modular services from this repository, replacing the nixpkgs copy.
    default = ./environments/nixos;
    # Just the implementation, without the disable.
    modularServices = ./environments/nixos/systemd;
    # Just the disable, without the implementation.
    disableUpstream = ./environments/nixos/disable-upstream.nix;
    # Replacement for the option-documentation registry that disableUpstream
    # removes.
    documentation = import ./environments/nixos/documentation.nix {
      inherit lib serviceModules;
    };
  };

  overlays = {
    # Adds `pkgs.modularServices.*`. Overrides nothing, so no rebuilds.
    default = import ./overlays { inherit serviceModules; };
    # Opt-in: repoints `pkgs.<pkg>.services.*` at this repository.
    packageServices = import ./overlays/package-services.nix { inherit serviceModules; };
  };
}
