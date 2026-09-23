# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Derived from `nixos/modules/services/databases/postgresql.nix` in nixpkgs:
# the systemd part of that module. The portable part is in
# `modular-services/postgresql/service.nix`.
#
# Differences from upstream:
#
# - A service module cannot declare users, so the units use `DynamicUser` with
#   the name in `postgresql.superUser`.
# - A service module cannot declare targets, so there is no
#   `postgresql.target`. The main unit wants the `-setup` unit, and the
#   `-setup` unit is part of the main unit. Order other services after the
#   `-setup` unit.
# - The package is not added to `environment.systemPackages`.
#
# TODO: `DynamicUser` gives an unknown UID, so a `dataDir` outside `/var/lib`
# must be writable for that UID. A static user needs a host-level module.
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
    filter
    getAttr
    hasPrefix
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkOption
    optionalString
    pipe
    sortProperties
    types
    versionAtLeast
    ;

  cfg = config.postgresql;

  groupAccessAvailable = versionAtLeast cfg.finalPackage.version "11.0";

  extensionNames = map lib.getName cfg.finalPackage.installedExtensions;
  extensionInstalled = extension: lib.elem extension extensionNames;

  stateDirectory =
    if hasPrefix "/var/lib/" cfg.dataDir then lib.removePrefix "/var/lib/" cfg.dataDir else null;

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

  timeoutSec = 120;
in
{
  _class = "service";
  imports = [ ./default.nix ];

  options.postgresql.systemCallFilter = mkOption {
    type = types.attrsOf (
      types.coercedTo types.bool (enable: { inherit enable; }) (
        types.submodule (
          { name, ... }:
          {
            options = {
              enable = mkEnableOption "${name} in postgresql's syscall filter";
              priority = mkOption {
                default =
                  if hasPrefix "@" name then
                    500
                  else if hasPrefix "~@" name then
                    1000
                  else
                    1500;
                defaultText = literalExpression ''
                  if hasPrefix "@" name then 500 else if hasPrefix "~@" name then 1000 else 1500
                '';
                type = types.int;
                description = ''
                  Set the priority of the system call filter setting. Later declarations
                  override earlier ones. The higher the number, the later it is added
                  to the filterset.
                '';
              };
            };
          }
        )
      )
    );
    defaultText = literalExpression ''
      {
        "@system-service" = true;
        "~@privileged" = true;
        "~@resources" = true;
      }
    '';
    description = ''
      Configures the syscall filter for the PostgreSQL unit. The keys are
      declarations for `SystemCallFilter` as described in {manpage}`systemd.exec(5)`.

      The value is a boolean: `true` adds the attribute name to the syscall filter-set,
      `false` doesn't. Settings with a higher priority are added after filter settings
      with a lower priority.
    '';
  };

  config = {
    postgresql.systemCallFilter = lib.mkMerge [
      (lib.mapAttrs (lib.const lib.mkDefault) {
        "@system-service" = true;
        "~@privileged" = true;
        "~@resources" = true;
      })
      (lib.mkIf (lib.any extensionInstalled [ "citus" ]) {
        "getpriority" = true;
        "setpriority" = true;
      })
    ];

    systemd.service =
      { name, ... }:
      {
        description = "PostgreSQL Server";

        after = [ "network.target" ];
        wants = [ "${name}-setup.service" ];

        environment.PGDATA = cfg.dataDir;

        path = [ cfg.finalPackage ];

        preStart = ''
          if ! test -e ${cfg.dataDir}/PG_VERSION; then
            # Cleanup the data directory.
            rm -f ${cfg.dataDir}/*.conf

            # Initialise the database.
            initdb -U ${cfg.superUser} ${escapeShellArgs cfg.initdbArgs}

            # See the setup unit.
            touch "${cfg.dataDir}/.first_startup"
          fi
        '';

        serviceConfig = lib.mkMerge [
          {
            User = cfg.superUser;
            Group = cfg.superUser;
            DynamicUser = true;
            RuntimeDirectory = "postgresql";

            # Shut down Postgres using SIGINT ("Fast Shutdown mode").  See
            # https://www.postgresql.org/docs/current/server-shutdown.html
            KillSignal = "SIGINT";
            KillMode = "mixed";

            # Give Postgres a decent amount of time to clean up after
            # receiving systemd's SIGINT.
            TimeoutSec = timeoutSec;

            # Hardening
            CapabilityBoundingSet = [ "" ];
            DevicePolicy = "closed";
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            MemoryDenyWriteExecute = lib.mkDefault (cfg.settings.jit == "off");
            NoNewPrivileges = true;
            LockPersonality = true;
            PrivateDevices = true;
            PrivateMounts = true;
            ProcSubset = "pid";
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            RemoveIPC = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_NETLINK" # used for network interface enumeration
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = pipe cfg.systemCallFilter [
              (mapAttrsToList (name: v: v // { inherit name; }))
              (filter (getAttr "enable"))
              sortProperties
              (map (getAttr "name"))
            ];
            UMask = if groupAccessAvailable then "0027" else "0077";
          }
          (lib.mkIf (stateDirectory == null) {
            # The user provides their own data directory
            ReadWritePaths = [ cfg.dataDir ];
          })
          (lib.mkIf (stateDirectory != null) {
            # Provision the data directory
            StateDirectory = stateDirectory;
            StateDirectoryMode = if groupAccessAvailable then "0750" else "0700";
          })
        ];

        unitConfig =
          let
            maxTries = 5;
            bufferSec = 5;
          in
          {
            RequiresMountsFor = "${cfg.dataDir}";

            # The max. time needed to perform `maxTries` start attempts of systemd
            # plus a bit of buffer time (bufferSec) on top.
            StartLimitIntervalSec = timeoutSec * maxTries + bufferSec;
            StartLimitBurst = maxTries;
          };
      };

    systemd.services.setup =
      { name, ... }:
      let
        main = lib.removeSuffix "-setup" name;
      in
      {
        description = "PostgreSQL Setup Scripts";

        requires = [ "${main}.service" ];
        after = [ "${main}.service" ];
        partOf = [ "${main}.service" ];

        serviceConfig = {
          User = cfg.superUser;
          Group = cfg.superUser;
          DynamicUser = true;
          Type = "oneshot";
          RemainAfterExit = true;
        }
        # A `DynamicUser` unit gets access to the data directory only through
        # its own `StateDirectory` or `ReadWritePaths`.
        // (
          if stateDirectory == null then
            { ReadWritePaths = [ cfg.dataDir ]; }
          else
            { StateDirectory = stateDirectory; }
        );

        path = [
          cfg.finalPackage
          pkgs.systemd
        ];
        environment.PGPORT = toString cfg.settings.port;

        # Wait for PostgreSQL to be ready to accept connections.
        script = ''
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
          while ! check-connection 2> /dev/null; do
              if ! systemctl is-active --quiet ${main}.service; then exit 1; fi
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
        '';
      };
  };
}
