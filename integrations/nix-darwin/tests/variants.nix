# Evaluates every nix-darwin variant in `../modular`, and checks the launchd
# daemons and `/etc` files that it makes. It only evaluates the system:
# building it needs a Darwin builder.
{
  lib,
  pkgs,
  evalSystem,
}:

let
  system =
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

        # The variant does not declare the user of the server.
        users.knownUsers = [ "postgres" ];
        users.knownGroups = [ "postgres" ];
        users.users.postgres = {
          uid = 400;
          gid = 400;
        };
        users.groups.postgres.gid = 400;
      }
    )).config;

  failed = lib.filter (a: !a.assertion) system.assertions;

  postgresql = system.launchd.daemons.postgresql-default;
  setup = system.launchd.daemons.postgresql-default-setup;
  psqlSchema = system.system.services.postgresql-default.postgresql.package.psqlSchema;
in
assert lib.assertMsg (failed == [ ]) (lib.concatMapStringsSep "\n" (a: a.message) failed);
assert postgresql.serviceConfig.Label == "org.nixos.postgresql-default";
assert postgresql.serviceConfig.KeepAlive == true;
assert postgresql.environment.PGDATA == "/var/lib/postgresql-default/${psqlSchema}";
assert lib.hasInfix "initdb -D" postgresql.script;
assert lib.hasInfix "exec /usr/bin/sudo -u postgres --" postgresql.script;
assert lib.hasInfix "/etc/system-services/postgresql-default/postgresql.conf" postgresql.script;
assert lib.hasInfix "pg_is_in_recovery" setup.script;
assert setup.serviceConfig.KeepAlive == false;
assert system.environment.etc ? "system-services/postgresql-default/postgresql.conf";
pkgs.writeText "nix-darwin-variants" (
  builtins.toJSON {
    daemons = lib.attrNames system.launchd.daemons;
    etc = lib.attrNames system.environment.etc;
    # Forces the evaluation of the whole system, but does not build it.
    toplevel = builtins.unsafeDiscardStringContext system.system.build.toplevel.drvPath;
  }
)
