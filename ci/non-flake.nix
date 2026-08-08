# Proof that nothing here needs a flake.
#
# Two things have to hold, and neither fails loudly on its own:
#
#   - A NixOS configuration must evaluate from `import ../. { inherit lib; }`
#     alone, with no `self` anywhere in the chain. `disable-proof.nix` covers
#     the disable itself; this covers reaching it without flake machinery.
#   - Every output outside `per-system.nix` must be system-independent. That is
#     the assumption `flake.nix` rests on when it publishes those once and the
#     rest keyed by system, and getting it wrong makes an output either
#     unreachable or dependent on `builtins.currentSystem`, which no flake may
#     evaluate.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  # Called the way a consumer would: no `system`, no `src`, no flake.
  base = import ../. {
    inherit lib nixpkgs pkgs;
  };

  perSystem = import ./per-system.nix;

  unknown = lib.subtractLists (lib.attrNames base) perSystem;

  # The same call with everything system-shaped removed. Anything reachable
  # from an output outside `perSystem` that touches one of these throws here,
  # naming itself in the trace.
  systemFree = import ../. {
    inherit lib;
    system = throw "ci/per-system.nix: this output was evaluated for a system";
    pkgs = throw "ci/per-system.nix: this output was evaluated against a package set";
    nixpkgs = throw "ci/per-system.nix: this output evaluated the pinned nixpkgs";
  };

  portable = builtins.deepSeq (lib.removeAttrs systemFree perSystem) "system-independent";

  # A system built purely out of `base`: the module, and a service module from
  # it, with nothing threaded through from the flake.
  eval = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit lib;
    system = null;
    modules = [
      (nixpkgs + "/nixos/modules/misc/nixpkgs/read-only.nix")
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

assert lib.assertMsg (unknown == [ ]) ''
  non-flake-consumer: ci/per-system.nix names outputs default.nix does not
  produce:

  ${lib.concatMapStringsSep "\n" (n: "  - ${n}") unknown}

  flake.nix would publish each of them as an empty attribute set keyed by
  system.
'';

assert lib.assertMsg (unit != null) ''
  non-flake-consumer: `system.services.tlshd` produced no systemd unit when the
  configuration was built from `import ./. { }` rather than from the flake.
'';

pkgs.runCommand "non-flake-consumer" { } ''
  echo 'outputs: ${toString (lib.attrNames base)}'
  echo 'per system: ${toString perSystem}'
  echo 'the rest: ${portable}'
  echo 'system.services.tlshd -> systemd.services.tlshd'
  touch $out
''
