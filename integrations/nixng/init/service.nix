# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2025 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Derived from `../../finix/finit/service.nix`, which is derived from
# `modules/finit/service.nix` in finix-modular-services
# (https://github.com/DigitalBrewStudios/finix-modular-services).
#
# TODO: NixNG's `init.services` has no reload command and no readiness
# protocol. Thus `process.reloadSignal`, `process.reloadCommand` and
# `notificationProtocol` have no effect here.
{ config, lib, ... }:
let
  inherit (lib)
    mkDefault
    mkOption
    types
    ;
in
{
  _class = "service";

  imports = [ (lib.mkAliasOptionModule [ "init" "service" ] [ "init" "services" "" ]) ];

  options = {
    init.services = mkOption {
      type = types.lazyAttrsOf types.deferredModule;
      default = { };
      description = ''
        NixNG init services for this modular service, as modules for NixNG's
        `init.services.<name>`. The name of the init service is the name of
        the modular service, followed by `-<name>` when `<name>` is not `""`.

        `init.service` is an alias of `init.services.""`.
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
    init.services."" = {
      enabled = mkDefault true;
      execStart = mkDefault (lib.escapeShellArgs config.process.argv);
    };
  };
}
