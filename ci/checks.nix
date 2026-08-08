# Repo-level checks that are not tied to a single integration.
#
# These use the same `{ kind, integration, drv }` shape as an integration's
# `tests/default.nix`, so `ci/matrix.nix` covers them too and CI really builds
# them. `nix flake check --no-build` would otherwise only instantiate them.
#
# `checks` is the merged set these become part of, which the manual lists a
# chapter of. Only names and `kind`/`integration` are read from it, so `docs`
# defining one of its entries does not make it depend on itself.
{
  lib,
  nixpkgs,
  self,
  pkgs,
  checks,
}:

let
  # `disabledModules` matches with `builtins.elem` and ignores keys that match
  # nothing, so a rename upstream would turn
  # integrations/nixos/disable-upstream.nix into a silent no-op.
  # integrations/nixos/tests/disable-proof.nix catches that
  # from the effect side; this catches it from the cause side, with a message
  # that names the file to update.
  #
  # Read out of the module itself rather than restated here, so the guard cannot
  # end up checking a key the disable no longer uses.
  inherit (import ../integrations/nixos/disable-upstream.nix) disabledModules;

  missing = lib.filter (p: !builtins.pathExists "${nixpkgs}/nixos/modules/${p}") disabledModules;

  check = drv: {
    kind = "eval";
    integration = "repo";
    inherit drv;
  };
in

assert lib.assertMsg (missing == [ ]) ''
  disable-keys-exist: the pinned nixpkgs no longer has:

  ${lib.concatMapStringsSep "\n" (p: "  - nixos/modules/${p}") missing}

  `disabledModules` silently ignores keys that match nothing, so
  integrations/nixos/disable-upstream.nix needs updating.
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
      ${lib.concatMapStringsSep "\n" (p: "echo 'found nixos/modules/${p}'") disabledModules}
      touch $out
    ''
  );

  # The consumer surface evaluates, and is complete, without a flake.
  non-flake-consumer = check (
    import ./non-flake.nix {
      inherit
        lib
        nixpkgs
        self
        pkgs
        ;
    }
  );

  # Every service module must be documented; see doc/registry.nix.
  docs-registry-complete = check (import ../doc/registry-complete.nix { inherit lib self pkgs; });

  # Every output must be described; see doc/outputs.nix.
  docs-outputs-complete = check (
    import ../doc/outputs-complete.nix {
      inherit
        lib
        nixpkgs
        self
        pkgs
        ;
    }
  );

  # The manual renders, with both option references substituted in.
  docs = check (
    import ../doc {
      inherit
        lib
        self
        pkgs
        checks
        ;
    }
  );
}
