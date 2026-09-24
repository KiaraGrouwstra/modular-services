# Evaluates every NixBSD variant in `../modular`, and checks the rc services
# and `/etc` files that it makes. It only evaluates the system: building it
# needs a cross-compiled FreeBSD.
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
        # The NixBSD module, to check that both can exist together.
        services.postgresql.enable = true;

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

  postgresql = system.freebsd.rc.services.postgresql-default;
  args = postgresql.shellVariables.command_args;
  psqlSchema = system.system.services.postgresql-default.postgresql.package.psqlSchema;
in
assert lib.assertMsg (failed == [ ]) (lib.concatMapStringsSep "\n" (a: a.message) failed);
assert
  lib.take 2 args == [
    "-u"
    "postgres"
  ];
assert lib.any (lib.hasSuffix "/bin/postgres") args;
assert postgresql.environment.PGDATA == "/var/lib/postgresql-default/${psqlSchema}";
assert lib.hasInfix "initdb -U postgres" postgresql.hooks.start_precmd;
assert lib.hasInfix "pg_is_in_recovery" postgresql.hooks.start_postcmd;
assert system.environment.etc ? "system-services/postgresql-default/postgresql.conf";
pkgs.writeText "nixbsd-variants" (
  builtins.toJSON {
    args = map builtins.unsafeDiscardStringContext args;
    etc = lib.attrNames system.environment.etc;
    # Forces the evaluation of the whole system, but does not build it.
    toplevel = builtins.unsafeDiscardStringContext system.system.build.toplevel.drvPath;
  }
)
