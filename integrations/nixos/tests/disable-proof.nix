# Proof that the eval-time disable in ../disable-upstream.nix actually took
# effect, and that what remains is this repo's copy.
#
# `disabledModules` matches with `builtins.elem`, so a key that no longer names
# an upstream module is ignored without a word. Both assertions below fail
# loudly in that case, and they fail at instantiation time, so
# `nix flake check --no-build` catches them.
{
  lib,
  self,
  pkgs,
  evalModules,
  evalSystem,
}:

let
  # Negative: with *only* the disable applied, nothing may declare
  # `system.services` any more. This is the assertion that catches an upstream
  # rename turning `disabledModules` into a silent no-op.
  disabledOnly = evalModules [ self.nixosModules.disableUpstream ];
  upstreamRemoved = !(disabledOnly.options.system ? services);

  # Positive: with our module, every declaration site of `system.services` must
  # live under this flake's store path. This catches the subtler failure where
  # both copies load and their `attrsOf submoduleWith` types merge without
  # complaint.
  ours = evalSystem { };
  declarations = map toString ours.options.system.services.declarations;
  foreign = lib.filter (d: !lib.hasPrefix "${self}" d) declarations;
in

assert lib.assertMsg upstreamRemoved ''
  nixos-disable-proof: `options.system.services` still exists with only
  `disableUpstream` loaded.

  The keys in integrations/nixos/disable-upstream.nix no longer match the
  pinned nixpkgs, so the in-tree modular services were not removed. Check
  whether `nixos/modules/system/service/systemd/system.nix` was renamed
  upstream, and update the key list.
'';

assert lib.assertMsg (declarations != [ ]) ''
  nixos-disable-proof: `options.system.services` has no declarations at all.
  Expected it to be declared by integrations/nixos/systemd/system.nix.
'';

assert lib.assertMsg (foreign == [ ]) ''
  nixos-disable-proof: `options.system.services` is declared outside this flake:

  ${lib.concatMapStringsSep "\n" (d: "  - ${d}") foreign}

  Both the upstream and the local copy appear to be loaded, and their option
  types merged. Expected every declaration under ${self}.
'';

pkgs.runCommand "nixos-disable-proof"
  {
    passthru = {
      inherit declarations;
    };
  }
  ''
    echo "upstream system.services removed:  yes"
    echo "system.services declared by:"
    ${lib.concatMapStringsSep "\n" (d: "echo '  - ${d}'") declarations}
    touch $out
  ''
