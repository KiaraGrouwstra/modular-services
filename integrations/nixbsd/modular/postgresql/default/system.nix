# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: 2024 Artemis Tosini, Audrey Dutcher, and NixOS/nixbsd contributors
#
# Derived from `modules/services/databases/postgresql.nix` in NixBSD
# (https://github.com/nixos-bsd/nixbsd) and from the setup unit in
# `nixos/modules/services/databases/postgresql.nix` in nixpkgs. The portable
# part is in `modular-services/postgresql/service.nix`.
#
# Differences from the NixBSD module:
#
# - The configuration files are in `/etc/system-services/<name>/`, not in
#   the data directory.
# - The `start_precmd` hook creates the data directory and the socket
#   directory, as a service module cannot declare tmpfiles.
#
# TODO: a service module cannot declare users. Thus the host must declare the
# user and group `postgresql.superUser` with `users.users` and
# `users.groups`, as the NixBSD module does.
#
# TODO: `daemon -P` forwards only `SIGTERM` to the server, thus the server
# gets `SIGTERM` ("Smart Shutdown mode") and not `SIGINT`, and there is no
# reload.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStrings
    concatStringsSep
    escapeShellArg
    escapeShellArgs
    mapAttrsToList
    optionalString
    ;

  cfg = config.postgresql;

  dataDir = escapeShellArg cfg.dataDir;
  owner = "${cfg.superUser}:${cfg.superUser}";
  asSuperUser = "sudo -E -u ${escapeShellArg cfg.superUser}";

  generateClauseSqlStatements =
    user:
    mapAttrsToList (
      n: v:
      let
        directive = lib.toUpper (lib.replaceStrings [ "_" ] [ " " ] n);
      in
      if builtins.isBool v then
        (if v then directive else "NO${directive}")
      else if builtins.isString v then
        "${directive} '${v}'"
      else
        "${directive} ${toString v}"
    ) user.ensureClauses;

  generateAlterRoleSQL =
    user:
    let
      clauseSqlStatements = generateClauseSqlStatements user;
    in
    if clauseSqlStatements == [ ] then
      ""
    else
      ''ALTER ROLE "${user.name}" ${concatStringsSep " " clauseSqlStatements};'';

  generateUserSetupScript =
    user:
    let
      dbOwnershipStmt = optionalString user.ensureDBOwnership ''
        psql -tAc 'ALTER DATABASE "${user.name}" OWNER TO "${user.name}";'
      '';

      alterRoleSQL = generateAlterRoleSQL user;

      userClauses = optionalString (alterRoleSQL != "") ''
        psql -tAc ${escapeShellArg alterRoleSQL}
      '';
    in
    ''
      psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${user.name}'" | grep -q 1 || psql -tAc 'CREATE USER "${user.name}"'
      ${userClauses}
      ${dbOwnershipStmt}
    '';

  pidfile = "/run/modular-${config.freebsd.meta.servicePrefix}.pid";
in
{
  _class = "service";
  imports = [ ./default.nix ];

  freebsd.rc.service = {
    description = "PostgreSQL Server";

    rcorderSettings.REQUIRE = [ "NETWORKING" ];

    environment.PGDATA = cfg.dataDir;

    path = [
      cfg.finalPackage
      pkgs.sudo
      pkgs.gnugrep
    ];

    # The server runs as `postgresql.superUser`, not as the user that
    # `../../../freebsd/system.nix` makes for each service.
    shellVariables.command_args = lib.mkForce (
      [
        "-u"
        cfg.superUser
        "-P"
        pidfile
        "--"
      ]
      ++ config.freebsd.rc.mainCommand
    );

    hooks.start_precmd = ''
      mkdir -p ${dataDir} /run/postgresql
      chown ${owner} ${dataDir} /run/postgresql
      chmod 0750 ${dataDir}

      if ! test -e ${dataDir}/PG_VERSION; then
        # Cleanup the data directory.
        rm -f ${dataDir}/*.conf ${dataDir}/.first_startup

        # Initialise the database.
        ${asSuperUser} initdb -U ${cfg.superUser} ${escapeShellArgs cfg.initdbArgs}

        # See start_postcmd.
        ${asSuperUser} touch ${dataDir}/.first_startup
      fi
    '';

    # Wait for PostgreSQL to be ready to accept connections.
    hooks.start_postcmd = ''
      psql() {
        ${asSuperUser} PGPORT=${toString cfg.settings.port} psql "$@"
      }

      MAINPID=$(check_pidfile "$pidfile" "$command")
      if test -z "$MAINPID"; then
        echo "PostgreSQL server died"
        return 1
      fi

      # If we're in standby mode, don't perform any setup
      if test -f ${dataDir}/standby.signal; then
        echo "Skipping setup because PostgreSQL is in standby mode"
        return 0
      fi

      # Wait until the server accepts connections and is not in recovery.
      while test "$(psql -d postgres -tAc 'SELECT pg_is_in_recovery()' 2> /dev/null)" != f; do
        if ! kill -0 "$MAINPID"; then return 1; fi
        sleep 0.1
      done

      if test -e ${dataDir}/.first_startup; then
        ${optionalString (cfg.initialScript != null) ''
          psql -f "${cfg.initialScript}" -d postgres
        ''}
        rm -f ${dataDir}/.first_startup
      fi
    ''
    + optionalString (cfg.ensureDatabases != [ ]) ''
      ${concatMapStrings (database: ''
        psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${database}'" | grep -q 1 || psql -tAc 'CREATE DATABASE "${database}"'
      '') cfg.ensureDatabases}
    ''
    + ''
      ${concatMapStrings generateUserSetupScript cfg.ensureUsers}
    '';
  };
}
