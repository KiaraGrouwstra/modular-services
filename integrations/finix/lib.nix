# How to evaluate and test modular services in the finix integration.
{
  lib,
  inputs,
  self,
  pkgs,
}:

let
  finixModules = import (inputs.finix + "/modules");
in
rec {
  /**
    Evaluate a finix system with this repo's modular services. As `mkVm` in
    finix's `tests/lib` does, this imports all finix modules, the optional
    ones included.
  */
  evalSystem =
    module:
    lib.evalModules {
      class = "nixos";
      specialArgs.modules = finixModules;
      modules = lib.attrValues finixModules ++ [
        { nixpkgs.pkgs = pkgs; }
        self.finixModules.default
        module
      ];
    };

  /**
    Run a finix VM test. The arguments are those of `mkTest` in finix's
    `tests/lib`. Every node imports this repo's integration.
  */
  runTest =
    test:
    (import (inputs.finix + "/tests/lib") { inherit lib pkgs; }).mkTest (
      test
      // {
        nodes = lib.mapAttrs (_: node: {
          imports = [
            self.finixModules.default
            node
          ];
        }) test.nodes;
      }
    );
}
