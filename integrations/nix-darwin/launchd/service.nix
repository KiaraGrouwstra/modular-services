# The launchd part of a modular service in nix-darwin.
#
# Each service gets the `launchd.daemons` option. The daemon `""` runs
# `process.argv`, and the other daemons are for the service to define. The
# daemon names get the prefix of the service name, as in
# `integrations/nixos/systemd/`.
#
# TODO: launchd has no reload and no readiness protocol, thus
# `process.reloadSignal` and `notificationProtocol` have no effect here. To
# stop a daemon, launchd sends `SIGTERM`.
let
  serviceModule =
    prefix:
    {
      config,
      lib,
      name,
      ...
    }:
    let
      inherit (lib) mkOption types;
      servicePrefix = "${prefix}${name}";
    in
    {
      _class = "service";

      options = {
        launchd.daemons = mkOption {
          description = ''
            The launchd daemons of this service, as for the nix-darwin
            option `launchd.daemons`. The daemon `""` gets the name of the
            service, and the other daemons get the name of the service as a
            prefix.

            Note that this option contains _deferred_ modules. You cannot read
            values from this option.
          '';
          type = types.lazyAttrsOf types.deferredModule;
          default = { };
        };

        # Extends the portable `configData` option.
        configData = mkOption {
          type = types.lazyAttrsOf (
            types.submodule (
              { config, ... }:
              {
                config.path = lib.mkDefault "/etc/system-services/${servicePrefix}/${config.name}";
              }
            )
          );
        };

        # Extends the portable `services` option.
        services = mkOption {
          type = types.attrsOf (
            types.submoduleWith {
              class = "service";
              modules = [ (serviceModule "${servicePrefix}-") ];
            }
          );
          # Rendered by the portable docs instead.
          visible = false;
        };
      };

      config.launchd.daemons."" = {
        serviceConfig = {
          # As the nix-darwin option `script` does, wait for the Nix store
          # before the start. A variant can set `script` in place of this.
          ProgramArguments = lib.mkDefault (
            [
              "/bin/sh"
              "-c"
              ''/bin/wait4path /nix/store && exec "$@"''
              "sh"
            ]
            ++ config.process.argv
          );
          KeepAlive = true;
          RunAtLoad = true;
        };
      };
    };
in
serviceModule ""
