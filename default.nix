# Everything this repository offers, flake or no flake.
#
# `flake.nix` is a wrapper: it pins nixpkgs through `flake.lock` and maps the
# per-system outputs over the systems it supports. It adds no output of its own,
# so a non-flake consumer gets the same surface, `checks` and `packages`
# included, by calling this file with the arguments they care about.
#
# Nothing a consumer imports evaluates this repository's own nixpkgs. The NixOS
# module takes `lib` and `pkgs` from the configuration importing it, and
# `disable-upstream.nix` names the module it removes by a key relative to that
# configuration's `modulesPath`. Every argument below is lazy, so
# `import ./. { inherit lib; }` never touches `nixpkgs` at all.
#
# ```nix
# # in a NixOS configuration, with `src` however you fetched this repository
# { pkgs, ... }:
# let
#   modular-services = import src { inherit (pkgs) lib; };
# in
# {
#   imports = [ modular-services.nixosModules.default ];
#   system.services.tlshd.imports = [ (modular-services.modularServices.ktls-utils pkgs) ];
# }
# ```
{
  # The nixpkgs this repository is developed against, needed only by the
  # outputs that build something. Read out of `flake.lock` so there is one pin
  # rather than two, and so Dependabot moves it for flake and non-flake alike.
  nixpkgs ?
    let
      locked = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
    in
    builtins.fetchTarball {
      inherit (locked) url;
      sha256 = locked.narHash;
    },

  lib ? import (nixpkgs + "/lib"),

  system ? builtins.currentSystem,

  pkgs ? import nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  },

  # Where this source lives. The checks compare option declaration sites
  # against it, and the manual records it as the revision it documents.
  src ? ./.,
  revision ? "dirty",
}:

let
  modularServices = import ./modular-services { inherit lib; };

  consumer = {
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
      mkComplianceSuite = pkgs': pkgs'.callPackage ./compliance { };
    };

    /**
      The canonical way to consume a service: `modularServices.<pkg> pkgs` yields a
      module to import into `system.services.<name>`.
    */
    inherit modularServices;

    nixosModules = {
      # Modular services from this repository, replacing the nixpkgs copy.
      default = ./environments/nixos;
      # Just the implementation, without the disable.
      systemServices = ./environments/nixos/systemd;
      # Just the disable, without the implementation.
      disableUpstream = ./environments/nixos/disable-upstream.nix;
      # Replacement for the option-documentation registry that disableUpstream
      # removes.
      documentation = import ./environments/nixos/documentation.nix {
        inherit lib modularServices;
      };
    };

    overlays = {
      # Adds `pkgs.modularServices.*`. Overrides nothing, so no rebuilds.
      default = import ./overlays { inherit modularServices; };
      # Opt-in: repoints `pkgs.<pkg>.services.*` at this repository.
      passthruServices = import ./overlays/passthru-services.nix { inherit modularServices; };
    };
  };

  # What `self` is to a flake, for the tests and the manual: the outputs a
  # consumer sees, plus where this source came from. `outPath` is a string
  # rather than a path, so that a non-flake evaluation compares against the
  # working tree instead of copying it into the store.
  self = consumer // {
    outPath = toString src;
    inherit revision;
  };

  # Every environment's tests, discovered from environments/ on disk, plus the
  # repo-level checks. Both carry `{ kind, env, drv }`, which is what `checks`
  # and the CI matrix are derived from.
  checks =
    import ./ci/tests.nix {
      inherit
        lib
        nixpkgs
        self
        pkgs
        ;
    }
    // import ./ci/checks.nix {
      inherit
        lib
        nixpkgs
        self
        pkgs
        ;
    };
in

consumer
// {
  checks = lib.mapAttrs (_: c: c.drv) checks;

  packages.docs = import ./doc { inherit lib self pkgs; };

  devShells.default = pkgs.mkShellNoCC {
    packages = [
      pkgs.nixfmt-tree
      pkgs.jq
    ];
  };

  formatter = pkgs.nixfmt-tree;

  # Consumed only by .github/workflows/ci.yml.
  ci.matrix = import ./ci/matrix.nix { inherit lib checks; };
}
