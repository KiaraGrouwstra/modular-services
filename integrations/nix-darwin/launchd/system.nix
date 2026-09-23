# The `system.services` option of nix-darwin. It makes a launchd daemon from
# each daemon of a service, and an `/etc` file from each `configData` entry.
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

  makeEtcFiles =
    prefix: service:
    lib.mapAttrs' (_: cfg: {
      # `./service.nix` sets the path.
      name =
        assert lib.hasPrefix "/etc/system-services/" cfg.path;
        lib.removePrefix "/etc/" cfg.path;
      value = {
        inherit (cfg) enable source;
      };
    }) (service.configData or { })
    // concatMapAttrs (
      subServiceName: subService: makeEtcFiles (dash prefix subServiceName) subService
    ) service.services;

  makeDaemons =
    prefix: service:
    concatMapAttrs (daemonName: daemonModule: {
      # A function, as `launchd.daemons` reads an attribute set as `config`,
      # not as a module.
      ${dash prefix daemonName} = _: { imports = [ daemonModule ]; };
    }) service.launchd.daemons
    // concatMapAttrs (
      subServiceName: subService: makeDaemons (dash prefix subServiceName) subService
    ) service.services;

  modularServiceConfiguration = portable-lib.configure {
    serviceManagerPkgs = pkgs;
    extraRootModules = [ ./service.nix ];
    extraRootSpecialArgs = {
      # Exposed so the variants under `../modular/` can pull in their pure
      # base from `modularServices.<name>`.
      inherit pkgs modularServices;
    };
  };
in
{
  _class = "darwin";

  options = {
    system.services = mkOption {
      description = ''
        A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured as launchd daemons.
      '';
      type = types.attrsOf modularServiceConfiguration.serviceSubmodule;
      default = { };
      visible = "shallow";
    };

    modularServices = mkOption {
      type = types.attrsOf (types.attrsOf types.deferredModule);
      description = ''
        nix-darwin variants of the modular services, keyed by
        `<pkg>.<service>`.

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

    warnings = concatLists (
      mapAttrsToList (
        name: cfg: portable-lib.getWarnings (options.system.services.loc ++ [ name ]) cfg
      ) config.system.services
    );

    launchd.daemons = concatMapAttrs makeDaemons config.system.services;

    environment.etc = concatMapAttrs makeEtcFiles config.system.services;
  };
}
