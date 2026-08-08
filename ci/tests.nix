# Discover every integration's test set from the filesystem.
#
# An integration is any directory under `integrations/` containing a
# `tests/default.nix`. Its tests are exposed as `<integration>-<test>`, so
# dropping in `integrations/home-manager/` extends `checks`, `nix flake check`
# and the CI matrix without editing anything here or in the workflow.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  integrationsDir = ../integrations;

  isIntegration =
    name: type:
    (type == "directory") && builtins.pathExists (integrationsDir + "/${name}/tests/default.nix");

  integrations = lib.filterAttrs isIntegration (builtins.readDir integrationsDir);

  testsOf =
    name:
    lib.mapAttrs'
      (testName: test: {
        name = "${name}-${testName}";
        value = test // {
          integration = name;
          test = testName;
        };
      })
      (
        import (integrationsDir + "/${name}/tests") {
          inherit
            lib
            nixpkgs
            self
            pkgs
            ;
        }
      );
in

lib.foldl' lib.mergeAttrs { } (map testsOf (lib.attrNames integrations))
