# How to evaluate and test modular services in the NixOS integration.
#
# This reproduces what `nixos/tests/all-tests.nix` provides to in-tree tests,
# so that ported tests keep their original signatures.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

rec {
  /**
    Evaluate a NixOS system from `modules`, with `pkgs` fixed to the instance
    this repo was called with. Nothing from this repo is loaded; use
    `evalSystem` for that.

    Equivalent to `all-tests.nix`'s `evalSystem` minus our own modules:
    `system = null` removes the legacy entry point's non-hermetic default, so
    `nixpkgs.pkgs` plus `read-only.nix` fully determines the package set.

    `eval-config.nix` and `read-only.nix` are named by path rather than through
    `lib.nixosSystem` and `nixpkgs.nixosModules.readOnlyPkgs`, both of which
    nixpkgs adds in its own `flake.nix`. `nixpkgs` here is a source tree, which
    a flake is only one way to obtain.
  */
  evalModules =
    modules:
    import (nixpkgs + "/nixos/lib/eval-config.nix") {
      inherit lib;
      system = null;
      modules = [
        (nixpkgs + "/nixos/modules/misc/nixpkgs/read-only.nix")
        { nixpkgs.pkgs = pkgs; }
        testDefaults
      ]
      ++ modules;
    };

  /**
    Settings every evaluation here shares, so that eval-level tests evaluate a
    configuration the same way VM tests do.

    `documentation.nixos.enable` mirrors `nixos/lib/testing/nixos-test-base.nix`.
    Rendering the NixOS option manual is not what any test in this repository
    checks -- `packages.docs` covers documentation -- and leaving it on makes
    `system.build.toplevel` depend on `nixos-configuration-reference-manpage`,
    which builds every option description in nixpkgs, unrelated ones included.
  */
  testDefaults = {
    _class = "nixos";
    documentation.nixos.enable = false;
  };

  /**
    Evaluate a NixOS system with this repo's modular services in place of the
    nixpkgs ones. Drop-in replacement for `all-tests.nix`'s `evalSystem`.
  */
  evalSystem =
    module:
    evalModules [
      self.nixosModules.default
      module
    ];

  /**
    Run a NixOS VM test with this repo's modular services in place of the
    nixpkgs ones, on every node.

    Unlike `all-tests.nix`'s `runTest`, this returns the test derivation
    directly; there is no `callTest`/`findTests` layer to satisfy.
  */
  runTest =
    module:
    pkgs.testers.runNixOSTest {
      imports = [ module ];
      defaults = {
        imports = [ self.nixosModules.default ];
      };
    };
}
