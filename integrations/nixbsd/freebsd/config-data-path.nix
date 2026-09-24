# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 Artemis Tosini, Audrey Dutcher, and NixOS/nixbsd contributors
#
# Copied from `modules/system/service/freebsd/config-data-path.nix` in NixBSD
# (https://github.com/nixos-bsd/nixbsd).
# This module sets the path for configData entries in systemd services
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
        # Expose service prefix and data directory
        freebsd.meta = mkOption {
          readOnly = true;
          default = {
            dataDir = "/var/lib/system-services/${servicePrefix}";
            username = "m-${servicePrefix}";
            inherit servicePrefix;
          };
        };
        # Extend portable configData option
        configData = mkOption {
          type = types.lazyAttrsOf (
            types.submodule (
              { config, ... }:
              {
                config = {
                  path = lib.mkDefault "/etc/system-services/${servicePrefix}/${config.name}";
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
