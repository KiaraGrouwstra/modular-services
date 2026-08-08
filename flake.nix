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

      # The consumer surface, which is flake-agnostic and lives in ./default.nix.
      # Everything below adds to it; nothing below restates it, so a non-flake
      # consumer cannot end up with a subset of what a flake consumer gets.
      base = import ./. { inherit lib; };

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
    base
    // {
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
