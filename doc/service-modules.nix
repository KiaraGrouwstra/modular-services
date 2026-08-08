# Registry of the service modules whose options are rendered into the NixOS
# manual, and the module that renders them.
#
# `registry` must cover every attribute of `serviceModules`;
# `checks.docs-registry-complete` enforces that, so the registry cannot drift
# the way the nixpkgs original did (which was missing `easytier` and
# `holo-daemon`).
{ lib, serviceModules }:

rec {
  /**
    Names of `serviceModules` entries to document, in the order they appear in
    the manual.
  */
  registry = [
    "autopush-rs-autoconnect"
    "autopush-rs-autoendpoint"
    "easytier"
    "ghostunnel"
    "holo-daemon"
    "ktls-utils"
    "php"
    "snid"
  ];

  /**
    Renders documentation for modular services.
    For inclusion into `documentation.nixos.extraModules`.

    This replaces nixpkgs' `nixos/modules/misc/documentation/modular-services.nix`,
    which `environments/nixos/disable-upstream.nix` removes.
  */
  module =
    { pkgs, ... }:
    let
      /**
        Causes a modular service's docs to be rendered.
        This is an intermediate solution until we have "native" service docs in some nicer form.
      */
      fakeSubmodule =
        serviceModule:
        lib.mkOption {
          type = lib.types.submoduleWith {
            modules = [ serviceModule ];
          };
          description = "This is a [modular service](https://nixos.org/manual/nixos/unstable/#modular-services), which can be imported into a NixOS configuration using the [`system.services`](https://search.nixos.org/options?channel=unstable&show=system.services&query=modular+service) option.";
        };

      modularServicesModule = {
        options = lib.listToAttrs (
          map (name: {
            name = "<imports = [ (serviceModules.${name} pkgs) ]>";
            value = fakeSubmodule (serviceModules.${name} pkgs);
          }) registry
        );
      };
    in
    {
      _class = "nixos";

      documentation.nixos.extraModules = [
        modularServicesModule
      ];
    };
}
