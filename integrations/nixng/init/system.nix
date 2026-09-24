# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2003-2025 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Derived from `../../finix/finit/system.nix`, which is derived from
# `modules/default.nix` and `modules/finit/system.nix` in
# finix-modular-services
# (https://github.com/DigitalBrewStudios/finix-modular-services).
#
# TODO: NixNG has no `warnings` option. Thus the warnings of the modular
# services are not shown.
{
  lib,
  config,
  options,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatLists
    concatMapAttrs
    mapAttrsToList
    mkOption
    types
    ;

  portable-lib = import ../../../lib/services { inherit lib; };

  modularServices = import ../../../modular-services { inherit lib; };

  dash =
    before: after:
    if after == "" then
      before
    else if before == "" then
      after
    else
      "${before}-${after}";

  makeServices =
    prefix: service:
    concatMapAttrs (name: module: {
      # NixNG declares `init.services` with `types.submodule`, which reads an
      # attribute set as configuration only. A function can import modules.
      "${dash prefix name}" = _: {
        imports = [ module ];
      };
    }) service.init.services
    // concatMapAttrs (
      subServiceName: subService: makeServices (dash prefix subServiceName) subService
    ) service.services;

  makeEtcFiles =
    prefix: service:
    lib.mapAttrs' (name: cfg: {
      name =
        assert lib.hasPrefix "/etc/system-services" cfg.path;
        lib.removePrefix "/etc/" cfg.path;
      value = {
        inherit (cfg) enable source;
      };
    }) (service.configData or { })
    // concatMapAttrs (
      subServiceName: subService: makeEtcFiles (dash prefix subServiceName) subService
    ) service.services;

  modularServiceConfiguration = portable-lib.configure {
    serviceManagerPkgs = pkgs;
    extraRootModules = [
      ./service.nix
      # Not specific to systemd: it sets `configData.<name>.path` below
      # `/etc/system-services/`.
      ../../nixos/systemd/config-data-path.nix
    ];
    extraRootSpecialArgs = {
      # Exposed so the variants under `../modular/` can pull in their pure
      # base from `modularServices.<name>`.
      inherit pkgs modularServices;
    };
  };
in
{
  options = {
    system.services = mkOption {
      description = ''
        A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured as NixNG init services.
      '';
      type = types.attrsOf modularServiceConfiguration.serviceSubmodule;
      default = { };
      visible = "shallow";
    };

    modularServices = mkOption {
      type = types.attrsOf (types.attrsOf types.deferredModule);
      description = ''
        NixNG variants of the modular services, keyed by `<pkg>.<service>`.

        Import the variant in a service, e.g.:

        ```nix
        imports = [ config.modularServices.postgresql.default ];
        ```
      '';
      default = (import ../modular).system;
      defaultText = lib.literalExpression "(import ../modular).system";
    };
  };

  config = {
    assertions = concatLists (
      mapAttrsToList (
        name: cfg: portable-lib.getAssertions (options.system.services.loc ++ [ name ]) cfg
      ) config.system.services
    );

    init.services = concatMapAttrs (
      serviceName: topLevelService: makeServices serviceName topLevelService
    ) config.system.services;

    environment.etc = concatMapAttrs (
      serviceName: topLevelService: makeEtcFiles serviceName topLevelService
    ) config.system.services;
  };
}
