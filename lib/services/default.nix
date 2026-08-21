{ lib, ... }:
let
  inherit (lib)
    concatLists
    mapAttrsToList
    showOption
    types
    ;
in
rec {
  flattenMapServicesConfigToList =
    f: loc: config:
    f loc config
    ++ concatLists (
      mapAttrsToList (
        k: v:
        flattenMapServicesConfigToList f (
          loc
          ++ [
            "services"
            k
          ]
        ) v
      ) config.services
    );

  getWarnings = flattenMapServicesConfigToList (
    loc: config: map (msg: "in ${showOption loc}: ${msg}") config.warnings
  );

  getAssertions = flattenMapServicesConfigToList (
    loc: config:
    map (ass: {
      message = "in ${showOption loc}: ${ass.message}";
      assertion = ass.assertion;
    }) config.assertions
  );

  /**
    The portable service base, `service.nix`, with its non-module dependency
    applied: `importService { inherit pkgs; }` is a module. `configure` loads it
    by default; pass it, or a copy pinned from another revision, as
    `baseModules` to choose the base explicitly.

    lib.services.importService :: { pkgs :: AttrSet } -> Module
  */
  importService = lib.modules.importApply ./service.nix;

  /**
    Entrypoint for integrating modular services into a containing module system.

    Each containing system (NixOS, ...) calls `configure` to
    obtain a `serviceSubmodule` type for its services option. The returned submodule
    includes the portable service base and any service-manager-specific modules
    passed via `extraRootModules`.

    **Implementing for a new integration** (e.g. home-manager, nix-darwin):

    An integration lives in `integrations/<name>/` and provides exactly four
    files. See `integrations/README.md` for the full contract; this docstring
    covers the one that calls `configure`.

    `integrations/<name>/default.nix` is the module that a user of that
    configuration system imports. It declares the services option in terms of
    `configure`, and translates the resulting service tree into whatever the
    integration's service manager consumes:

    ```nix
    # integrations/darwin/default.nix
    { lib, config, pkgs, ... }:
    let
      portable-lib = import ../../lib/services { inherit lib; };

      modularServiceConfiguration = portable-lib.configure {
        serviceManagerPkgs = pkgs;
        # To load a different portable service base, set `baseModules` instead:
        #   baseModules = [ (portable-lib.importService { inherit pkgs; }) ];
        extraRootModules = [
          ./launchd/service.nix    # launchd-specific options (plist generation, etc.)
        ];
      };
    in
    {
      _class = "darwin";

      imports = [ ./disable-upstream.nix ];

      options.services = lib.mkOption {
        type = lib.types.attrsOf modularServiceConfiguration.serviceSubmodule;
        default = { };
      };

      config = {
        # Convert service tree -> launchd plists, assertions, etc.
        # (analogous to how NixOS converts to systemd units)
        launchd.agents = ...;
        assertions = ...;
        warnings = ...;
      };
    }
    ```

    The remaining three files are `disable-upstream.nix` (eval-time removal of
    that configuration system's in-tree copy, if it has one), `lib.nix`
    (`{ evalSystem, runTest, ... }`: how to evaluate and test there), and
    `tests/default.nix` (`{ <name> = { kind = "eval" | "vm"; drv; }; }`).
    `ci/tests.nix` discovers `integrations/` from the filesystem, so an
    integration that honours the contract is picked up by `checks`,
    `nix flake check` and CI with no further wiring.

    lib.services.configure :: AttrSet -> { serviceSubmodule :: SubmoduleType }

    # Inputs

    `serviceManagerPkgs`

    : 1\. A Nixpkgs instance used for built-in logic such as converting
    `configData.<path>.text` to a store path. Required unless `baseModules`
    is set.

    `baseModules`

    : 2\. Modules that replace the portable service base. They are loaded
    into the "root" service submodule and must handle propagation to
    sub-`services` themselves. Defaults to this repository's portable service
    base, `importService { pkgs = serviceManagerPkgs; }`. Set it to supply a
    different one, for example a `service.nix` pinned from another revision.

    `extraRootModules`

    : 3\. Modules to be loaded into the "root" service submodule, but not
    into its sub-`services`. That's the modules' own responsibility.
    Typically contains service-manager-specific option modules
    (e.g. systemd unit options, launchd plist options).

    `extraRootSpecialArgs`

    : 4\. Fixed module arguments provided alongside `extraRootModules`.

    # Output

    An attribute set.

    `serviceSubmodule`: a Module System option type which is a `submodule` with the portable modules and this function's inputs loaded into it.
  */
  configure =
    {
      serviceManagerPkgs ? throw "lib.services.configure: `serviceManagerPkgs` is required unless `baseModules` is set",
      baseModules ? [ (importService { pkgs = serviceManagerPkgs; }) ],
      extraRootModules ? [ ],
      extraRootSpecialArgs ? { },
    }:
    let
      serviceSubmodule = types.submoduleWith {
        class = "service";
        modules = baseModules ++ extraRootModules;
        specialArgs = extraRootSpecialArgs;
      };
    in
    {
      inherit serviceSubmodule;
    };
}
