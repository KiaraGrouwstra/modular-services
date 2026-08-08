# Repo-level checks that are not tied to a single environment.
#
# These use the same `{ kind, env, drv }` shape as an environment's
# `tests/default.nix`, so `ci/matrix.nix` covers them too and CI really builds
# them. `nix flake check --no-build` would otherwise only instantiate them.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  check = drv: {
    kind = "eval";
    env = "repo";
    inherit drv;
  };
in

{
  # Portable layer, pure eval. Upstream runs this as
  # `nix-instantiate --eval lib/services/test.nix`.
  lib-eval = check (
    pkgs.runCommand "lib-services-eval" { } ''
      echo ${import ../lib/services/test.nix { inherit lib; }}
      touch $out
    ''
  );
}
