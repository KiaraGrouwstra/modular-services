# The devenv part of a modular service. The system module in `./system.nix`
# imports this in every service and sub-service.
{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkDefault mkOption types;
in
{
  _class = "service";

  imports = [
    (lib.mkAliasOptionModule [ "devenv" "process" ] [ "devenv" "processes" "" ])
  ];

  options = {
    devenv.processes = mkOption {
      type = types.lazyAttrsOf types.deferredModule;
      default = { };
      description = ''
        devenv processes for this modular service, as modules for
        `processes.<name>`. The name of the process is the name of the modular
        service, followed by `-<name>` when `<name>` is not `""`.

        `devenv.process` is an alias of `devenv.processes.""`.
      '';
    };

    # devenv has no `/etc`. The service reads each file from the Nix store,
    # and `configData.<name>.enable` has no effect.
    configData = mkOption {
      type = types.lazyAttrsOf (
        types.submodule (
          { config, ... }:
          {
            config.path = mkDefault "${config.source}";
          }
        )
      );
    };

    # Extends the portable `services` option, so that sub-services also get
    # this logic.
    services = mkOption {
      type = types.attrsOf (
        types.submoduleWith {
          class = "service";
          modules = [ ./service.nix ];
        }
      );
    };
  };

  # devenv has no reload. A variant can set `ready` for readiness.
  #
  # TODO: devenv 2.0 has `ready.notify` for `notificationProtocol.systemd`,
  # but only its own process manager uses it. process-compose ignores it.
  config.devenv.processes."" = {
    exec = mkDefault (lib.escapeShellArgs config.process.argv);
  };
}
