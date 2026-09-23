# SPDX-License-Identifier: MIT AND MPL-2.0
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: 2021 Richard Brežák and NixNG contributors
#
# Derived from `modules/services/postgresql.nix` in NixNG
# (https://github.com/nix-community/NixNG) and from the setup unit in
# `nixos/modules/services/databases/postgresql.nix` in nixpkgs. The portable
# part is in `modular-services/postgresql/service.nix`.
#
# Differences from the NixNG module:
#
# - The configuration files are in `/etc/system-services/<name>/`, not in
#   the data directory.
# - The server runs as the service user from the start. `initdb` runs in the
#   start script before the server, as the same user.
# - The `initialScript`, `ensureDatabases` and `ensureUsers` steps run in a
#   separate `-setup` service, which waits until the server accepts
#   connections.
#
# TODO: a service module cannot declare users. Thus the host must declare the
# user and group `postgresql.superUser` with `users.users` and
# `users.groups`, as the NixNG module does.
#
# TODO: NixNG's `init.services` has no stop signal option, thus the server
# gets `SIGTERM` ("Smart Shutdown mode") and not `SIGINT`.
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

  owner = "${cfg.superUser}:${cfg.superUser}";

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

  # runit ignores `execStartPre`, thus `initdb` is in the start script.
  start = pkgs.writeShellScript "postgresql-start" ''
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

    exec ${escapeShellArgs config.process.argv}
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
      # The init system can start this service before the server is ready.
      # Thus wait at most 120 seconds.
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

  init.service = {
    user = cfg.superUser;
    group = cfg.superUser;
    environment.PGDATA = cfg.dataDir;

    ensureSomething.create.dataDir = {
      type = "directory";
      mode = "750";
      inherit owner;
      persistent = true;
      dst = cfg.dataDir;
    };

    ensureSomething.create.runSocket = {
      type = "directory";
      mode = "755";
      inherit owner;
      persistent = false;
      dst = "/run/postgresql/";
    };

    execStart = "${start}";
  };

  init.services.setup =
    { name, ... }:
    {
      enabled = true;
      type = "scripted";
      user = cfg.superUser;
      group = cfg.superUser;
      dependencies = [ (lib.removeSuffix "-setup" name) ];
      execStart = "${setup}";
    };
}
