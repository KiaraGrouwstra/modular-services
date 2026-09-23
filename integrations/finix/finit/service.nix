# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2025 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Derived from `modules/finit/service.nix` in finix-modular-services
# (https://github.com/DigitalBrewStudios/finix-modular-services). This version
# also sets `notify` from `notificationProtocol` and `exec-reload` from
# `process.reloadCommand`.
{ config, lib, ... }:
let
  inherit (lib) mkDefault mkIf mkOption types;

  notify = config.notificationProtocol;
in
{
  _class = "service";

  imports = [ (lib.mkAliasOptionModule [ "finit" "service" ] [ "finit" "services" "" ]) ];

  options = {
    finit.services = mkOption {
      type = types.lazyAttrsOf types.deferredModule;
      default = { };
      description = ''
        finit services for this modular service, as modules for finix's
        `finit.services.<name>`. The name of the finit service is the name of
        the modular service, followed by `-<name>` when `<name>` is not `""`.

        `finit.service` is an alias of `finit.services.""`.
      '';
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
    finit.services."" = {
      command = mkDefault (lib.escapeShellArgs config.process.argv);
      notify = mkIf (notify.systemd || notify.s6) (mkDefault (if notify.systemd then "systemd" else "s6"));
      # finit sets `$MAINPID`, which the default `reloadCommand` uses.
      exec-reload = mkIf (config.process.reloadCommand != null) (mkDefault config.process.reloadCommand);
    };
  };
}
