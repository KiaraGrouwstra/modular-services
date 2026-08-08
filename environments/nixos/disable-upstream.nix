# Remove the in-tree copy of modular services from a NixOS evaluation, at eval
# time only. The nixpkgs input is never patched and no fork branch is involved.
#
# The keys are given in the module-directory-relative form that
# `lib/modules.nix` resolves against `modulesPath` (`<nixpkgs>/nixos/modules`),
# rather than as `"${nixpkgs}/nixos/modules/..."` store paths. The relative form
# matches whatever nixpkgs the *consumer* evaluates against, which is the whole
# point: a downstream user pinning a different nixpkgs still gets the upstream
# copy disabled.
#
# Matching is `builtins.elem`, so a key that no longer names a module is
# silently ignored. Two things guard against that failure mode:
#
#   - `tests/disable-proof.nix` asserts that `options.system ? services` is
#     `false` when only this module is loaded.
#   - `ci/checks.nix` asserts the files still exist in the pinned nixpkgs.
#
# This also applies inside NixOS VM tests: `nixos/lib/testing/nodes.nix` routes
# node evaluation through the same `eval-config.nix`.
{
  _class = "nixos";

  disabledModules = [
    # Declares `system.services`; also the sole live consumer of the in-tree
    # `lib/services`, via a relative import.
    "system/service/systemd/system.nix"
    # A stub upstream, disabled for hygiene so the whole subsystem comes from
    # one place.
    "system/service/systemd/user.nix"
    # Documentation registry naming `pkgs.<pkg>.services.*`; superseded by
    # `nixosModules.documentation`.
    "misc/documentation/modular-services.nix"
  ];
}
