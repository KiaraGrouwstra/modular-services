# How to evaluate and test modular services in the services-flake integration.
{
  lib,
  inputs,
  self,
  pkgs,
}:

let
  processCompose = import (inputs.process-compose-flake + "/nix/lib.nix") { inherit pkgs; };
in
rec {
  /**
    Evaluate a process-compose-flake configuration with services-flake and
    this repo's modular services.
  */
  evalSystem =
    module:
    processCompose.evalModules {
      modules = [
        (inputs.services-flake + "/nix/process-compose")
        self.processComposeModules.default
        module
      ];
    };

  /**
    Run a process-compose test in the build sandbox: the `test` process of
    `module` runs, and the test passes when it exits with 0.
  */
  runTest = module: (evalSystem module).config.outputs.check;
}
