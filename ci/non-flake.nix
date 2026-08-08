# Proof that the consumer surface does not need a flake.
#
# `flake.nix` wraps `default.nix` and may only add per-system outputs to it. Two
# things have to hold for that to stay true, and neither fails loudly on its own:
#
#   - A NixOS configuration must evaluate from `import ../. { inherit lib; }`
#     alone, with no `self` anywhere in the chain. `disable-proof.nix` covers the
#     disable itself; this covers reaching it without flake machinery.
#   - The flake must expose the same consumer attributes as `default.nix`. An
#     output added to `flake.nix` only would be invisible to everyone consuming
#     this repository through `npins`, `fetchTarball` or a subtree.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  base = import ../. { inherit lib; };

  # The three groups a new consumer-facing output would land in. `serviceModules`
  # is compared as a whole, being a flat set of the same shape.
  surface = [
    "lib"
    "nixosModules"
    "overlays"
    "serviceModules"
  ];

  divergent = lib.filter (
    group: lib.attrNames base.${group} != lib.attrNames (self.${group} or { })
  ) surface;

  # A system built purely out of `base`: the module, and a service module from
  # it, with nothing threaded through from the flake.
  eval = lib.nixosSystem {
    modules = [
      nixpkgs.nixosModules.readOnlyPkgs
      { nixpkgs.pkgs = pkgs; }
      base.nixosModules.default
      {
        _class = "nixos";
        documentation.nixos.enable = false;
        system.services.tlshd.imports = [ (base.serviceModules.ktls-utils pkgs) ];
      }
    ];
  };

  unit = eval.config.systemd.services.tlshd or null;
in

assert lib.assertMsg (divergent == [ ]) ''
  non-flake-consumer: flake.nix and default.nix disagree on:

  ${lib.concatMapStringsSep "\n" (
    g:
    "  - ${g}: flake has ${toString (lib.attrNames (self.${g} or { }))}, default.nix has ${
        toString (lib.attrNames base.${g})
      }"
  ) divergent}

  flake.nix must only add per-system outputs to what default.nix exposes.
'';

assert lib.assertMsg (unit != null) ''
  non-flake-consumer: `system.services.tlshd` produced no systemd unit when the
  configuration was built from `import ./. { inherit lib; }` rather than from
  the flake.
'';

pkgs.runCommand "non-flake-consumer" { } ''
  echo 'consumer surface: ${toString surface}'
  echo 'system.services.tlshd -> systemd.services.tlshd'
  touch $out
''
