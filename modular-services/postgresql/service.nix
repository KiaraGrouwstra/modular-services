# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Derived from `nixos/modules/services/databases/postgresql.nix` in nixpkgs.
# This file keeps only the portable part: the options, the configuration files
# and the command line. The steps that the upstream module does in its
# service manager (`initdb`, the setup scripts, users and hardening) are in the
# environment variants, `integrations/<environment>/modular/postgresql/`.

# Non-module dependencies (`importApply`)
{
  writeText,
  runCommand,
  stdenv,
}:

{
  config,
  lib,
  name,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    const
    elem
    filterAttrs
    literalExpression
    mapAttrsToList
    mkAfter
    mkBefore
    mkDefault
    mkMerge
    mkOption
    types
    isString
    ;

  cfg = config.postgresql;

  toStr =
    value:
    if true == value then
      "yes"
    else if false == value then
      "no"
    else if isString value then
      "'${lib.replaceStrings [ "'" ] [ "''" ] value}'"
    else
      toString value;

  configFile = writeText "postgresql.conf" (
    concatStringsSep "\n" (
      mapAttrsToList (n: v: "${n} = ${toStr v}") (filterAttrs (const (x: x != null)) cfg.settings)
    )
  );

  # Upstream adds this check to `system.checks`. Modular services have no
  # such option, so the check is a dependency of the configuration file.
  checkedConfigFile = runCommand "postgresql.conf" { } ''
    mkdir conf
    cp ${configFile} conf/postgresql.conf
    ${cfg.finalPackage}/bin/postgres -Dconf -C config_file >/dev/null
    cp ${configFile} $out
  '';
in
{
  _class = "service";

  meta.maintainers = lib.teams.postgres.members;

  options.postgresql = {
    enableJIT = lib.mkEnableOption "JIT support";

    package = mkOption {
      type = types.package;
      example = literalExpression "pkgs.postgresql_17";
      defaultText = "The postgresql package that provided this module.";
      description = ''
        The package being used by postgresql.
      '';
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      default =
        let
          withJit = if cfg.enableJIT then cfg.package.withJIT else cfg.package.withoutJIT;
        in
        if cfg.extensions == [ ] then withJit else withJit.withPackages cfg.extensions;
      defaultText = "with config.postgresql; package.withPackages extensions";
      description = ''
        The postgresql package that will effectively be used by the service.
        It consists of the base package with plugins applied to it.
      '';
    };

    checkConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Check the syntax of the configuration file at compile time";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/${name}/${cfg.package.psqlSchema}";
      defaultText = literalExpression ''"/var/lib/''${name}/''${config.postgresql.package.psqlSchema}"'';
      example = "/var/lib/postgresql/17";
      description = ''
        The data directory for PostgreSQL. An environment can change the
        default, and can create the default directory before the PostgreSQL
        server starts. Refer to the environment for which directories it
        creates.
      '';
    };

    authentication = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Defines how users authenticate themselves to the server. See the
        [PostgreSQL documentation for pg_hba.conf](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
        for details on the expected format of this option. By default,
        peer based authentication will be used for users connecting
        via the Unix socket, and md5 password authentication will be
        used for users connecting via TCP. Any added rules will be
        inserted above the default rules. If you'd like to replace the
        default rules entirely, you can use `lib.mkForce` in your
        module.
      '';
    };

    identMap = mkOption {
      type = types.lines;
      default = "";
      example = ''
        map-name-0 system-username-0 database-username-0
        map-name-1 system-username-1 database-username-1
      '';
      description = ''
        Defines the mapping from system users to database users.

        See the [auth doc](https://postgresql.org/docs/current/auth-username-maps.html).

        There is a default map "postgres" which is used for local peer authentication
        as the postgres superuser role.
        For example, to allow the root user to login as the postgres superuser, add:

        ```
        postgres root postgres
        ```
      '';
    };

    initdbArgs = mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [
        "--data-checksums"
        "--allow-group-access"
      ];
      description = ''
        Additional arguments passed to `initdb` during data dir
        initialisation.
      '';
    };

    initialScript = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression ''
        pkgs.writeText "init-sql-script" '''
          alter user postgres with password 'myPassword';
        ''';'';
      description = ''
        A file containing SQL statements to execute on first startup.
      '';
    };

    ensureDatabases = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Ensures that the specified databases exist.
        This option will never delete existing databases, especially not when the value of this
        option is changed. This means that databases created once through this option or
        otherwise have to be removed manually.
      '';
      example = [
        "gitea"
        "nextcloud"
      ];
    };

    ensureUsers = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = ''
                Name of the user to ensure.
              '';
            };

            ensureDBOwnership = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Grants the user ownership to a database with the same name.
                This database must be defined manually in
                {option}`postgresql.ensureDatabases`.
              '';
            };

            ensureClauses = mkOption {
              description = ''
                An attrset of clauses to grant to the user. Under the hood this uses the
                [ALTER USER syntax](https://www.postgresql.org/docs/current/sql-alteruser.html) for each attrName where
                the attrValue is true in the attrSet:
                `ALTER USER user.name WITH attrName`
              '';
              example = literalExpression ''
                {
                  superuser = true;
                  createrole = true;
                  createdb = true;
                  connection_limit = 5;
                }
              '';
              default = { };
              type = types.submodule {
                freeformType = types.attrsOf (
                  types.oneOf [
                    types.str
                    types.int
                    types.bool
                  ]
                );
              };
            };
          };
        }
      );
      default = [ ];
      description = ''
        Ensures that the specified users exist.
        The PostgreSQL users will be identified using peer authentication. This authenticates the Unix user with the
        same name only, and that without the need for a password.
        This option will never delete existing users or remove DB ownership of databases
        once granted with `ensureDBOwnership = true;`. This means that this must be
        cleaned up manually when changing after changing the config in here.
      '';
      example = literalExpression ''
        [
          {
            name = "nextcloud";
          }
          {
            name = "superuser";
            ensureDBOwnership = true;
          }
        ]
      '';
    };

    enableTCPIP = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether PostgreSQL should listen on all network interfaces.
        If disabled, the database can only be accessed via its Unix
        domain socket or via TCP connections to localhost.
      '';
    };

    extensions = mkOption {
      type = with types; coercedTo (listOf path) (path: _ignorePg: path) (functionTo (listOf path));
      default = _: [ ];
      example = literalExpression "ps: with ps; [ postgis pg_repack ]";
      description = ''
        List of PostgreSQL extensions to install.
      '';
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = types.attrsOf (
          types.oneOf [
            types.bool
            types.float
            types.int
            types.str
          ]
        );
        options = {
          shared_preload_libraries = mkOption {
            type = types.nullOr (types.coercedTo (types.listOf types.str) (concatStringsSep ",") types.commas);
            default = null;
            example = literalExpression ''[ "auto_explain" "anon" ]'';
            description = ''
              List of libraries to be preloaded.
            '';
          };

          log_line_prefix = mkOption {
            type = types.str;
            default = "[%p] ";
            example = "%m [%p] ";
            description = ''
              A printf-style string that is output at the beginning of each log line.
              Upstream default is `'%m [%p] '`, i.e. it includes the timestamp. We do
              not include the timestamp, because the service manager's log usually has it.
            '';
          };

          port = mkOption {
            type = types.port;
            default = 5432;
            description = ''
              The port on which PostgreSQL listens.
            '';
          };
        };
      };
      default = { };
      description = ''
        PostgreSQL configuration. Refer to
        <https://www.postgresql.org/docs/current/config-setting.html#CONFIG-SETTING-CONFIGURATION-FILE>
        for an overview of {file}`postgresql.conf`.

        ::: {.note}
        String values will automatically be enclosed in single quotes. Single quotes will be
        escaped with two single quotes as described by the upstream documentation linked above.
        :::
      '';
      example = literalExpression ''
        {
          log_connections = true;
          log_statement = "all";
          logging_collector = true;
          log_disconnections = true;
        }
      '';
    };

    superUser = mkOption {
      type = types.str;
      default = "postgres";
      description = ''
        PostgreSQL superuser account to use for various operations.
      '';
    };
  };

  config = {
    warnings =
      let
        unstableState =
          if lib.hasInfix "beta" cfg.package.version then
            "in beta"
          else if lib.hasInfix "rc" cfg.package.version then
            "a release candidate"
          else
            null;
      in
      lib.optional (unstableState != null)
        "PostgreSQL ${lib.versions.major cfg.package.version} is currently ${unstableState}, and is not advised for use in production environments.";

    assertions = map (
      { name, ensureDBOwnership, ... }:
      {
        assertion = ensureDBOwnership -> elem name cfg.ensureDatabases;
        message = ''
          For each database user defined with `postgresql.ensureUsers` and
          `ensureDBOwnership = true;`, a database with the same name must be defined
          in `postgresql.ensureDatabases`.

          Offender: ${name} has not been found among databases.
        '';
      }
    ) cfg.ensureUsers;

    postgresql.settings = {
      hba_file = config.configData."pg_hba.conf".path;
      ident_file = config.configData."pg_ident.conf".path;
      log_destination = "stderr";
      listen_addresses = if cfg.enableTCPIP then "*" else "localhost";
      jit = mkDefault (if cfg.enableJIT then "on" else "off");
    };

    postgresql.authentication = mkMerge [
      (mkBefore "# Generated file; do not edit!")
      (mkAfter ''
        # default value of postgresql.authentication
        local all ${cfg.superUser}         peer map=postgres
        local all all              peer
        host  all all 127.0.0.1/32 md5
        host  all all ::1/128      md5
      '')
    ];

    # The default allows to login with the same database username as the current system user.
    # This is the default for peer authentication without a map, but needs to be made explicit
    # once a map is used.
    postgresql.identMap = mkAfter ''
      postgres ${cfg.superUser} ${cfg.superUser}
    '';

    configData = {
      "postgresql.conf".source =
        if cfg.checkConfig && stdenv.buildPlatform.canExecute stdenv.hostPlatform then
          checkedConfigFile
        else
          configFile;
      "pg_hba.conf".source = writeText "pg_hba.conf" cfg.authentication;
      "pg_ident.conf".source = writeText "pg_ident.conf" cfg.identMap;
    };

    process.argv = [
      "${cfg.finalPackage}/bin/postgres"
      "-D"
      cfg.dataDir
      "--config-file=${config.configData."postgresql.conf".path}"
    ];

    process.reloadSignal = "HUP";

    notificationProtocol.systemd = true;
  };
}
