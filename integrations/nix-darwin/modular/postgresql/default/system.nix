# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: 2017 Daiderd Jordan
#
# Derived from `modules/services/postgresql/default.nix` in nix-darwin
# (https://github.com/nix-darwin/nix-darwin) and from the setup unit in
# `nixos/modules/services/databases/postgresql.nix` in nixpkgs. The portable
# part is in `modular-services/postgresql/service.nix`.
#
# Differences from the nix-darwin module:
#
# - The server is a launchd daemon, not a user agent. The daemon starts as
#   `root`, makes the data directory, and then runs `initdb` and the server
#   as `postgresql.superUser` with `sudo`.
# - The configuration files are in `/etc/system-services/<name>/`, not in
#   the data directory.
# - The `setup` daemon does the steps of the setup unit in nixpkgs:
#   `initialScript`, `ensureDatabases` and `ensureUsers`.
#
# TODO: a service module cannot declare users. Thus the host must declare the
# user and group `postgresql.superUser` with `users.users`, `users.groups`,
# `users.knownUsers` and `users.knownGroups`.
#
# TODO: launchd sends `SIGTERM` to `sudo`, and `sudo` sends it to the server.
# Thus the server gets `SIGTERM` ("Smart Shutdown mode") and not `SIGINT`.
#
# TODO: launchd has no dependencies between daemons. Thus the `setup` daemon
# runs only when launchd loads it, and not each time that the server starts.
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
  # The `sudo` of macOS, as it must be setuid.
  asSuperUser = "/usr/bin/sudo -u ${escapeShellArg cfg.superUser} --";

  # The time in seconds that the `setup` daemon waits for the server.
  timeoutSec = 120;

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
in
{
  _class = "service";
  imports = [ ./default.nix ];

  launchd.daemons."" = {
    environment.PGDATA = cfg.dataDir;

    script = ''
      mkdir -p ${dataDir}
      chown ${owner} ${dataDir}
      chmod 0750 ${dataDir}

      if ! test -e ${dataDir}/PG_VERSION; then
        # Cleanup the data directory.
        rm -f ${dataDir}/*.conf ${dataDir}/.first_startup

        # Initialise the database.
        ${asSuperUser} ${cfg.finalPackage}/bin/initdb -D ${dataDir} -U ${escapeShellArg cfg.superUser} ${escapeShellArgs cfg.initdbArgs}

        # See the setup daemon.
        ${asSuperUser} touch ${dataDir}/.first_startup
      fi

      exec ${asSuperUser} ${escapeShellArgs config.process.argv}
    '';
  };

  launchd.daemons.setup = {
    path = [ pkgs.gnugrep ];

    script = ''
      psql() {
        ${asSuperUser} ${cfg.finalPackage}/bin/psql --port=${toString cfg.settings.port} "$@"
      }

      # If we're in standby mode, don't perform any setup
      if test -f ${dataDir}/standby.signal; then
        echo "Skipping setup because PostgreSQL is in standby mode"
        exit 0
      fi

      # Wait until the server accepts connections and is not in recovery.
      tries=0
      while test "$(psql -d postgres -tAc 'SELECT pg_is_in_recovery()' 2> /dev/null)" != f; do
        tries=$((tries + 1))
        if test "$tries" -gt ${toString (timeoutSec * 10)}; then
          echo "PostgreSQL server is not ready"
          exit 1
        fi
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

    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = false;
    };
  };
}
