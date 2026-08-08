{
  description = "Modular services: services defined as modules, portable across environments using Nix modules.";

  inputs = {
    # The channel tarball rather than the git repository: it is a fraction of
    # the download, and it only advances once Hydra has built the channel, so
    # every derivation this flake evaluates is already in cache.nixos.org.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Every environment's tests, discovered from environments/ on disk, plus
      # the repo-level checks. Both carry `{ kind, env, drv }`, which is what
      # `checks` and the CI matrix are derived from.
      checksFor =
        pkgs:
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
    {
      lib = {
        /**
          The portable layer, instantiated against a caller-supplied `lib`.
          This is the entry point for implementing a new environment; see the
          `configure` docstring in lib/services/default.nix.
        */
        servicesFor = lib': import ./lib/services { lib = lib'; };

        /**
          The portable layer, against this flake's nixpkgs.
        */
        services = self.lib.servicesFor lib;

        /**
          The environment-agnostic compliance suite, instantiated for a package
          set. See compliance/README.md for the arguments it takes.
        */
        mkComplianceSuite = pkgs: pkgs.callPackage ./compliance { };
      };

      /**
        The canonical way to consume a service: `serviceModules.<pkg> pkgs`
        yields a module to import into `system.services.<name>`.
      */
      serviceModules = import ./service-modules { inherit lib; };

      nixosModules = {
        # Modular services from this repository, replacing the nixpkgs copy.
        default = ./environments/nixos;
        # Just the implementation, without the disable.
        modularServices = ./environments/nixos/systemd;
        # Just the disable, without the implementation.
        disableUpstream = ./environments/nixos/disable-upstream.nix;
        # Replacement for the option-documentation registry that
        # disableUpstream removes.
        documentation = import ./environments/nixos/documentation.nix {
          inherit lib;
          inherit (self) serviceModules;
        };
      };

      overlays = {
        # Adds `pkgs.modularServices.*`. Overrides nothing, so no rebuilds.
        default = import ./overlays { inherit (self) serviceModules; };
        # Opt-in: repoints `pkgs.<pkg>.services.*` at this repository.
        packageServices = import ./overlays/package-services.nix { inherit (self) serviceModules; };
      };

      checks = forAllSystems (pkgs: lib.mapAttrs (_: c: c.drv) (checksFor pkgs));

      packages = forAllSystems (pkgs: {
        docs = import ./doc { inherit lib self pkgs; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.nixfmt-tree
            pkgs.jq
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      # Consumed only by .github/workflows/ci.yml.
      ci = forAllSystems (pkgs: {
        matrix = import ./ci/matrix.nix {
          inherit lib;
          checks = checksFor pkgs;
        };
      });
    };
}
