# Evaluates every finix variant in `../modular`, and checks the finit
# services and `/etc` files that it makes.
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
        services.getty.enable = true;
        services.mdevd.enable = true;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
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

  postgresql = system.finit.services.postgresql-default;
in
assert lib.assertMsg (failed == [ ]) (lib.concatMapStringsSep "\n" (a: a.message) failed);
assert lib.hasInfix "--config-file=/etc/system-services/postgresql-default/postgresql.conf"
  postgresql.command;
assert postgresql.user == "postgres";
assert postgresql.notify == "systemd";
assert lib.hasInfix "kill -HUP" postgresql.exec-reload;
assert system.environment.etc ? "system-services/postgresql-default/pg_hba.conf";
pkgs.writeText "finix-variants" (
  builtins.toJSON {
    inherit (postgresql) command;
    etc = lib.attrNames system.environment.etc;
  }
)
