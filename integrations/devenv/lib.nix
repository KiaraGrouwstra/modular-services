# How to evaluate and test modular services in the devenv integration.
{
  lib,
  inputs,
  self,
  pkgs,
}:

rec {
  /**
    Evaluate a devenv configuration with this repo's modular services. This
    does what devenv's `lib.mkEval` does, without devenv's flake inputs.
  */
  evalSystem =
    module:
    lib.evalModules {
      class = "devenv";
      specialArgs.inputs = { };
      modules = [
        (inputs.devenv + "/src/modules/top-level.nix")
        {
          _module.args.pkgs = pkgs;
          devenv.flakesIntegration = true;
          devenv.warnOnNewVersion = false;
          # The CLI sets it to the project directory. The tests set the
          # directories that they use.
          devenv.root = "/devenv-root";
          # devenv builds `devenv-tasks` with the nixpkgs that devenv locks,
          # and gets that nixpkgs through import from derivation. The
          # `--no-build` check in CI cannot do import from derivation. The
          # tests do not use `devenv-tasks`, thus a stub replaces it.
          task.package = lib.mkDefault (
            pkgs.writeShellScriptBin "devenv-tasks" ''
              echo "devenv-tasks is not available in this evaluation" >&2
              exit 1
            ''
          );
        }
        self.devenvModules.default
        module
      ];
    };

  /**
    Run a devenv test in the build sandbox: process-compose runs the processes
    of `module`, and the test passes when the `test` process exits with 0.

    devenv usually runs each process through `devenv-tasks`. That is a Rust
    program that the test does not build. Thus the test runs each `exec`
    directly, as devenv does for a process that `devenv-tasks` does not wrap.
  */
  runTest =
    module:
    let
      inherit (evalSystem module) config;
      settings = config.process.managers.process-compose.settings;
      settingsFile = (pkgs.formats.yaml { }).generate "process-compose.yaml" (
        settings
        // {
          log_location = "./process-compose.log";
          processes = lib.mapAttrs (
            name: process:
            process
            // {
              command = config.processes.${name}.exec;
              shutdown = process.shutdown // {
                inherit (config.processes.${name}.shutdown) signal;
              };
            }
            // lib.optionalAttrs (name == "test") {
              availability = process.availability // {
                exit_on_end = true;
              };
            }
          ) settings.processes;
        }
      );
    in
    pkgs.runCommand "devenv-test"
      {
        nativeBuildInputs = [ pkgs.process-compose ];
      }
      ''
        export HOME=$TMP
        cd $HOME
        process-compose --no-server up --tui=false --config ${settingsFile}
        touch $out
      '';
}
