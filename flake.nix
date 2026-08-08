{
  description = "Modular services: services defined as modules, portable across NixOS, Home Manager and nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
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

      # The repo-level checks, carrying `{ kind, env, drv }`, which is what
      # `checks` is derived from.
      checksFor =
        pkgs:
        import ./ci/checks.nix {
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
      };

      checks = forAllSystems (pkgs: lib.mapAttrs (_: c: c.drv) (checksFor pkgs));

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.nixfmt-tree
            pkgs.jq
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
