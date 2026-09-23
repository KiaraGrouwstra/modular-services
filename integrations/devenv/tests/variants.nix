# Evaluates every devenv variant in `../modular`, and checks the processes
# that it makes. devenv's own `services.postgres` is on too, to show that both
# can be in one configuration.
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
        services.postgres.enable = true;

        system.services = lib.concatMapAttrs (
          pkg: svcs:
          lib.mapAttrs' (svc: _: {
            name = "${pkg}-${svc}";
            value.imports = [ config.modularServices.${pkg}.${svc} ];
          }) svcs
        ) config.modularServices;
      }
    )).config;

  inherit (config) processes;

  postgresql = processes.postgresql-default;
  setup = processes.postgresql-default-setup;
in
assert processes ? postgres;
assert lib.hasInfix "/nix/store/" postgresql.exec;
assert postgresql.ready.exec != null;
assert postgresql.shutdown.signal == 2;
assert setup.after == [ "devenv:processes:postgresql-default@ready" ];
assert setup.process-compose.depends_on.postgresql-default.condition == "process_healthy";
assert
  config.system.services.postgresql-default.postgresql.dataDir
  == "${config.devenv.state}/postgresql-default";
pkgs.writeText "devenv-variants" (
  builtins.toJSON {
    inherit (postgresql) exec;
    processes = lib.attrNames processes;
  }
)
