# The process-compose part of a modular service. The system module in
# `./system.nix` imports this in every service and sub-service.
{
  config,
  lib,
  name,
  ...
}:
let
  inherit (lib) mkDefault mkOption types;
in
{
  _class = "service";

  imports = [
    (lib.mkAliasOptionModule [ "processCompose" "process" ] [ "processCompose" "processes" "" ])
  ];

  options = {
    processCompose.processes = mkOption {
      type = types.lazyAttrsOf types.deferredModule;
      default = { };
      description = ''
        process-compose processes for this modular service, as modules for
        `settings.processes.<name>`. The name of the process is the name of
        the modular service, followed by `-<name>` when `<name>` is not `""`.

        `processCompose.process` is an alias of `processCompose.processes.""`.
      '';
    };

    # process-compose has no `/etc`. The service reads each file from the
    # Nix store, and `configData.<name>.enable` has no effect.
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

  config = {
    # process-compose has no reload and no readiness notification. A variant
    # can set `readiness_probe` in its place.
    processCompose.processes."" = {
      command = mkDefault (lib.escapeShellArgs config.process.argv);
    };
  };
}
