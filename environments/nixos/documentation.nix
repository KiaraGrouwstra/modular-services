# Renders per-service option documentation into the NixOS manual.
#
# This replaces nixpkgs' `nixos/modules/misc/documentation/modular-services.nix`,
# which `./disable-upstream.nix` removes. It lives here rather than under `doc/`
# because it is a NixOS module: it is `_class = "nixos"` and writes to
# `documentation.nixos.extraModules`, both of which mean nothing to any other
# environment. What *is* shared is the list of services to document, which comes
# from `doc/registry.nix`.
#
# Exported as `nixosModules.documentation`. It is not part of
# `nixosModules.default`, because rendering the NixOS manual is a cost a system
# should opt into.
{ lib, serviceModules }:

{ pkgs, ... }:

let
  registry = import ../../doc/registry.nix;

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
}
