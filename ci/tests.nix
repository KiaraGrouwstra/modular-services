# Discover every environment's test set from the filesystem.
#
# An environment is any directory under `environments/` containing a
# `tests/default.nix`. Its tests are exposed as `<env>-<test>`, so dropping in
# `environments/home-manager/` extends `checks`, `nix flake check` and the CI
# matrix without editing anything here or in the workflow.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  environmentsDir = ../environments;

  isEnvironment =
    name: type:
    (type == "directory") && builtins.pathExists (environmentsDir + "/${name}/tests/default.nix");

  environments = lib.filterAttrs isEnvironment (builtins.readDir environmentsDir);

  testsOf =
    name:
    lib.mapAttrs'
      (testName: test: {
        name = "${name}-${testName}";
        value = test // {
          env = name;
          test = testName;
        };
      })
      (
        import (environmentsDir + "/${name}/tests") {
          inherit
            lib
            nixpkgs
            self
            pkgs
            ;
        }
      );
in

lib.foldl' lib.mergeAttrs { } (map testsOf (lib.attrNames environments))
