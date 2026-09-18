# Analogous to ../system/config-data-path.nix but scoped per user.
# This file is a *function to* a module.
#
# Documentation: integrations/nixos/README.md#per-user-services
#
# configData paths land under the per-user profile:
#   /etc/profiles/per-user/$USER/etc/xdg/user-services/...
userName:
let
  setPathsModule =
    prefix:
    { lib, name, ... }:
    let
      inherit (lib) mkOption types;
      servicePrefix = "${prefix}${name}";
    in
    {
      _class = "service";
      options = {
        configData = mkOption {
          type = types.lazyAttrsOf (
            types.submodule (
              { config, ... }:
              {
                config = {
                  path = lib.mkDefault "/etc/profiles/per-user/${userName}/etc/xdg/user-services/${servicePrefix}/${config.name}";
                };
              }
            )
          );
        };
        services = mkOption {
          type = types.attrsOf (
            types.submoduleWith {
              modules = [
                (setPathsModule "${servicePrefix}-")
              ];
            }
          );
        };
      };
    };
in
setPathsModule ""
