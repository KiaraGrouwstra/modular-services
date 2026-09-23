# Evaluates every services-flake variant in `../modular`, and checks the
# processes that it makes.
{
  lib,
  pkgs,
  evalSystem,
}:

let
  config =
    (evalSystem (
      { config, ... }:
      {
        system.services = lib.concatMapAttrs (
          pkg: svcs:
          lib.mapAttrs' (svc: _: {
            name = "${pkg}-${svc}";
            value.imports = [ config.modularServices.${pkg}.${svc} ];
          }) svcs
        ) config.modularServices;
      }
    )).config;

  inherit (config.settings) processes;

  postgresql = processes.postgresql-default;
in
assert lib.hasInfix "--config-file=/nix/store/" postgresql.command;
assert postgresql.depends_on.postgresql-default-init.condition == "process_completed_successfully";
assert postgresql.shutdown.signal == 2;
assert
  processes.postgresql-default-setup.depends_on.postgresql-default.condition == "process_healthy";
pkgs.writeText "services-flake-variants" (
  builtins.toJSON {
    inherit (postgresql) command;
    processes = lib.attrNames processes;
  }
)
