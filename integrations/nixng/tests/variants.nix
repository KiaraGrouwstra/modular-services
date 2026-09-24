# Evaluates every NixNG variant in `../modular` with the init system
# `initSystem`, and checks the init services and `/etc` files that it makes.
# The derivation depends on the system's `toplevel`, thus the init system
# configuration must build.
{
  lib,
  pkgs,
  evalSystem,
  initSystem,
}:

let
  system =
    (evalSystem (
      { config, ... }:
      {
        ${initSystem}.enable = true;

        # The NixNG module, to check that both can exist together.
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql;
        };

        # See the TODO in `../modular/postgresql/default/system.nix`.
        users.users.postgres = {
          uid = config.ids.uids.postgres;
          group = "postgres";
        };
        users.groups.postgres.gid = config.ids.gids.postgres;

        system.services = lib.concatMapAttrs (
          pkg: svcs:
          lib.mapAttrs' (svc: _: {
            name = "${pkg}-${svc}";
            value.imports = [ config.modularServices.${pkg}.${svc} ];
          }) svcs
        ) config.modularServices;
      }
    )).config;

  failed = lib.filter (a: !a.assertion) system.assertions;

  postgresql = system.init.services.postgresql-default;
  setup = system.init.services.postgresql-default-setup;
in
assert lib.assertMsg (failed == [ ]) (lib.concatMapStringsSep "\n" (a: a.message) failed);
assert postgresql.enabled;
assert postgresql.user == "postgres";
assert
  postgresql.ensureSomething.create.dataDir.dst
  == "/var/lib/postgresql-default/${pkgs.postgresql.psqlSchema}";
assert lib.hasInfix "postgresql-start" postgresql.execStart;
assert setup.type == "scripted";
assert setup.dependencies == [ "postgresql-default" ];
assert system.environment.etc ? "system-services/postgresql-default/postgresql.conf";
pkgs.writeText "nixng-variants-${initSystem}" (
  builtins.toJSON {
    inherit (postgresql) execStart;
    etc = lib.attrNames system.environment.etc;
    toplevel = system.system.build.toplevel;
  }
)
