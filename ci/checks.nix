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
  # `disabledModules` matches with `builtins.elem` and ignores keys that match
  # nothing, so a rename upstream would turn environments/nixos/disable-upstream.nix
  # into a silent no-op. environments/nixos/tests/disable-proof.nix catches that
  # from the effect side; this catches it from the cause side, with a message
  # that names the file to update.
  disabledNixosModules = [
    "system/service/systemd/system.nix"
    "system/service/systemd/user.nix"
    "misc/documentation/modular-services.nix"
  ];

  missing = lib.filter (p: !builtins.pathExists "${nixpkgs}/nixos/modules/${p}") disabledNixosModules;

  check = drv: {
    kind = "eval";
    env = "repo";
    inherit drv;
  };
in

assert lib.assertMsg (missing == [ ]) ''
  disable-keys-exist: the pinned nixpkgs no longer has:

  ${lib.concatMapStringsSep "\n" (p: "  - nixos/modules/${p}") missing}

  `disabledModules` silently ignores keys that match nothing, so
  environments/nixos/disable-upstream.nix needs updating.
'';

{
  # Portable layer, pure eval. Upstream runs this as
  # `nix-instantiate --eval lib/services/test.nix`.
  lib-eval = check (
    pkgs.runCommand "lib-services-eval" { } ''
      echo ${import ../lib/services/test.nix { inherit lib; }}
      touch $out
    ''
  );

  # The guard above; a derivation so it shows up as a check.
  disable-keys-exist = check (
    pkgs.runCommand "disable-keys-exist" { } ''
      ${lib.concatMapStringsSep "\n" (p: "echo 'found nixos/modules/${p}'") disabledNixosModules}
      touch $out
    ''
  );
}
