# Declares `system.services` in a devenv configuration, and makes a devenv
# process for each process of each modular service.
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

  makeProcesses =
    prefix: service:
    concatMapAttrs (name: module: {
      # `processes.<name>` is a `types.submodule`, which reads an attrset as
      # `config` only. A function can have `imports`.
      "${dash prefix name}" = _: {
        imports = [ module ];
      };
    }) service.devenv.processes
    // concatMapAttrs (
      subServiceName: subService: makeProcesses (dash prefix subServiceName) subService
    ) service.services;

  modularServiceConfiguration = portable-lib.configure {
    serviceManagerPkgs = pkgs;
    extraRootModules = [ ./service.nix ];
    extraRootSpecialArgs = {
      # Exposed so the variants under `../modular/` can pull in their pure
      # base from `modularServices.<name>`, and find the devenv state and
      # runtime directories.
      inherit pkgs modularServices;
      inherit (config) devenv;
    };
  };
in
{
  options = {
    system.services = mkOption {
      description = ''
        A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured as devenv processes.
      '';
      type = types.attrsOf modularServiceConfiguration.serviceSubmodule;
      default = { };
      visible = "shallow";
    };

    modularServices = mkOption {
      type = types.attrsOf (types.attrsOf types.deferredModule);
      description = ''
        devenv variants of the modular services, keyed by
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

    processes = concatMapAttrs (
      serviceName: topLevelService: makeProcesses serviceName topLevelService
    ) config.system.services;
  };
}
