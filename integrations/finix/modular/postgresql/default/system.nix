# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Derived from `modules/services/postgresql/default.nix` in finix
# (https://github.com/finix-community/finix) and from the setup unit in
# `nixos/modules/services/databases/postgresql.nix` in nixpkgs. The portable
# part is in `modular-services/postgresql/service.nix`.
#
# Differences from the finix module:
#
# - The configuration files are in `/etc/system-services/<name>/`, not in
#   `/etc/postgresql/`.
# - The server logs to stderr, not to syslog, and finit keeps the log.
# - The `initialScript`, `ensureDatabases` and `ensureUsers` steps run in
#   `exec-start-ready`, when the server is ready.
#
# TODO: finit runs all scripts of a service as the service user, and a service
# module cannot declare users or directories. Thus the host must declare the
# user and group `postgresql.superUser`, and create `postgresql.dataDir` and
# `/run/postgresql` for that user. Do this with `users.users`, `users.groups`
# and `finit.tmpfiles.rules`, as the finix module does.
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
    escapeShellArgs
    mapAttrsToList
    optionalString
    ;

  cfg = config.postgresql;

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
        psql -tAc ${lib.escapeShellArg alterRoleSQL}
      '';
    in
    ''
      psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${user.name}'" | grep -q 1 || psql -tAc 'CREATE USER "${user.name}"'
      ${userClauses}
      ${dbOwnershipStmt}
    '';

  path = lib.makeBinPath [
    cfg.finalPackage
    pkgs.coreutils
    pkgs.gnugrep
  ];

  preStart = pkgs.writeShellScript "postgresql-pre-start" ''
    set -eu
    export PATH=${path}
    export PGDATA=${lib.escapeShellArg cfg.dataDir}

    if ! test -e ${cfg.dataDir}/PG_VERSION; then
      # Cleanup the data directory.
      rm -f ${cfg.dataDir}/*.conf

      # Initialise the database.
      initdb -U ${cfg.superUser} ${escapeShellArgs cfg.initdbArgs}

      # See the setup script.
      touch "${cfg.dataDir}/.first_startup"
    fi
  '';

  setup = pkgs.writeShellScript "postgresql-setup" (
    ''
      set -eu
      export PATH=${path}
      export PGPORT=${toString cfg.settings.port}

      # If we're in standby mode, don't perform any setup
      if [[ -f "${cfg.dataDir}/standby.signal" ]]; then
        echo "Skipping setup because PostgreSQL is in standby mode"
        exit 0
      fi

      check-connection() {
        psql -d postgres -v ON_ERROR_STOP=1 <<-'  EOF'
          SELECT pg_is_in_recovery() \gset
          \if :pg_is_in_recovery
          \i still-recovering
          \endif
        EOF
      }
      # finit runs this script when the server is ready. The server can still
      # be in recovery, thus wait at most 120 seconds.
      tries=1200
      while ! check-connection 2> /dev/null; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then exit 1; fi
        sleep 0.1
      done

      if test -e "${cfg.dataDir}/.first_startup"; then
        ${optionalString (cfg.initialScript != null) ''
          psql -f "${cfg.initialScript}" -d postgres
        ''}
        rm -f "${cfg.dataDir}/.first_startup"
      fi
    ''
    + optionalString (cfg.ensureDatabases != [ ]) ''
      ${concatMapStrings (database: ''
        psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${database}'" | grep -q 1 || psql -tAc 'CREATE DATABASE "${database}"'
      '') cfg.ensureDatabases}
    ''
    + ''
      ${concatMapStrings generateUserSetupScript cfg.ensureUsers}
    ''
  );
in
{
  _class = "service";
  imports = [ ./default.nix ];

  finit.service = {
    description = "PostgreSQL server";
    user = cfg.superUser;
    group = cfg.superUser;
    path = [ cfg.finalPackage ];
    environment.PGDATA = cfg.dataDir;
    conditions = [ "net/lo/up" ];
    log = true;

    exec-start-pre = "${preStart}";
    exec-start-ready = "${setup}";

    # Shut down Postgres using SIGINT ("Fast Shutdown mode"). See
    # https://www.postgresql.org/docs/current/server-shutdown.html
    exec-stop = "${pkgs.coreutils}/bin/kill -INT $MAINPID";

    # Give Postgres a decent amount of time to clean up after SIGINT.
    stop-timeout = 120;
  };
}
