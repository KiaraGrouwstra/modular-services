# SPDX-License-Identifier: MIT AND Apache-2.0
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: The devenv contributors
#
# Derived from `src/modules/services/postgres.nix` in devenv
# (https://github.com/cachix/devenv) and from the setup unit in
# `nixos/modules/services/databases/postgresql.nix` in nixpkgs. The portable
# part is in `modular-services/postgresql/service.nix`.
#
# The service has two processes:
#
# - `<name>` runs `initdb` when `postgresql.dataDir` has no database, then
#   starts the server. It is ready when `pg_isready` succeeds.
# - `<name>-setup` runs `initialScript`, `ensureDatabases` and `ensureUsers`
#   when the server is ready.
#
# Differences from the devenv module:
#
# - The configuration files stay in the Nix store, and the server reads them
#   from there. `initdb` does not write them.
# - The setup script runs in its own process, not in a temporary server
#   before the real one starts.
# - The options are those of the NixOS module, not those of devenv.
#
# devenv runs all processes as the user that starts it. Thus
# `postgresql.identMap` lets each system user connect as
# `postgresql.superUser` through the socket, which only that user can open.
#
# TODO: `ensureUsers` uses peer authentication, which needs a system user
# with the same name.
{
  config,
  devenv,
  lib,
  name,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStrings
    concatStringsSep
    escapeShellArgs
    hasPrefix
    head
    mapAttrsToList
    optionalString
    splitString
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

  # The server makes its socket in the first of `unix_socket_directories`. A
  # relative directory is relative to `postgresql.dataDir`.
  socketDir = head (splitString "," cfg.settings.unix_socket_directories);

  # devenv starts the processes in the project directory. A relative
  # `dataDir` is relative to that directory. The clients need an absolute
  # socket directory.
  environment = ''
    export PATH=${path}
    PGDATA=$(realpath -m ${lib.escapeShellArg cfg.dataDir})
    export PGDATA
    PGHOST=$(realpath -m ${
      if hasPrefix "/" socketDir then
        lib.escapeShellArg socketDir
      else
        "\"$PGDATA\"/${lib.escapeShellArg socketDir}"
    })
    export PGHOST
    export PGPORT=${toString cfg.settings.port}
    export PGUSER=${lib.escapeShellArg cfg.superUser}
  '';

  start = pkgs.writeShellScript "postgresql-start" ''
    set -eu
    ${environment}

    mkdir -p "$PGHOST"
    if ! test -e "$PGDATA/PG_VERSION"; then
      # Cleanup the data directory.
      mkdir -p "$PGDATA"
      rm -f "$PGDATA"/*.conf

      # Initialise the database.
      initdb -U ${cfg.superUser} ${escapeShellArgs cfg.initdbArgs}

      # See the setup script.
      touch "$PGDATA/.first_startup"
    fi

    exec ${escapeShellArgs config.process.argv}
  '';

  isReady = pkgs.writeShellScript "postgresql-is-ready" ''
    set -eu
    ${environment}
    pg_isready -d template1
  '';

  setup = pkgs.writeShellScript "postgresql-setup" (
    ''
      set -eu
      ${environment}

      # If we're in standby mode, don't perform any setup
      if [[ -f "$PGDATA/standby.signal" ]]; then
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
      # devenv runs this script when the server is healthy. The
      # server can still be in recovery, thus wait at most 120 seconds.
      tries=1200
      while ! check-connection 2> /dev/null; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then exit 1; fi
        sleep 0.1
      done

      if test -e "$PGDATA/.first_startup"; then
        ${optionalString (cfg.initialScript != null) ''
          psql -f "${cfg.initialScript}" -d postgres
        ''}
        rm -f "$PGDATA/.first_startup"
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

  postgresql.dataDir = lib.mkDefault "${devenv.state}/${name}";

  postgresql.settings.unix_socket_directories = lib.mkDefault "${devenv.runtime}/${name}";

  postgresql.identMap = lib.mkAfter ''
    postgres /^(.*)$ ${cfg.superUser}
  '';

  devenv.processes = {
    "" = {
      exec = "${start}";

      ready = {
        exec = "${isReady}";
        initial_delay = 2;
        probe_timeout = 4;
        failure_threshold = 5;
      };

      # Shut down Postgres using SIGINT ("Fast Shutdown mode"). See
      # https://www.postgresql.org/docs/current/server-shutdown.html
      shutdown.signal = 2;

      restart = {
        on = "on_failure";
        max = 5;
      };
    };

    # devenv-tasks starts the process after `after`. process-compose without
    # devenv-tasks uses `depends_on`.
    #
    # TODO: this can be a devenv task in place of a process.
    setup =
      { name, ... }:
      let
        main = lib.removeSuffix "-setup" name;
      in
      {
        exec = "${setup}";
        after = [ "devenv:processes:${main}@ready" ];
        restart.on = "never";
        process-compose.depends_on.${main}.condition = "process_healthy";
      };
  };
}
