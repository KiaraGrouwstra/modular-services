# The NixOS environment's test set.
#
# Contract (see ../../README.md): an attrset of
# `{ <name> = { kind = "eval" | "vm"; drv = <derivation>; }; }`.
#
# `kind` splits the CI matrix: `"eval"` tests build without a VM, `"vm"` tests
# need `/dev/kvm`. `ci/tests.nix` prefixes each name with the environment name,
# so `units` here becomes `checks.nixos-units`.
{
  lib,
  nixpkgs,
  self,
  pkgs,
}:

let
  nixosLib = import ../lib.nix {
    inherit
      lib
      nixpkgs
      self
      pkgs
      ;
  };

  inherit (nixosLib) evalModules evalSystem runTest;
  inherit (self) serviceModules;

  compliance = import ./compliance.nix {
    inherit
      pkgs
      self
      evalSystem
      runTest
      ;
  };

  eval = drv: {
    kind = "eval";
    inherit drv;
  };
  vm = drv: {
    kind = "vm";
    inherit drv;
  };

  # `php.buildEnv` wrapper from nixpkgs' `nixos/tests/php/default.nix`; the test
  # asserts that `apcu` is among the loaded extensions.
  php' = pkgs.php.buildEnv {
    extensions = { enabled, all }: with all; enabled ++ [ apcu ];
  };

  # Per-package VM tests. Each is a `nixosTest` module taking `serviceModules`
  # as a non-module dependency.
  pkgTests = {
    autopush-rs = ./packages/autopush-rs.nix;
    easytier = ./packages/easytier.nix;
    ghostunnel = ./packages/ghostunnel.nix;
    holo-daemon = ./packages/holo-daemon.nix;
    snid = ./packages/snid.nix;
    tlshd = ./packages/tlshd.nix;
  };
in

{
  # The crux: proof that the upstream copy is gone and ours is in its place.
  disable-proof = eval (
    import ./disable-proof.nix {
      inherit
        lib
        self
        pkgs
        evalModules
        evalSystem
        ;
    }
  );

  # Rendered systemd units for a representative service tree.
  units = eval (pkgs.callPackage ./units.nix { inherit evalSystem; });

  # `configData` -> `environment.etc`.
  etc = vm (runTest ./etc/test.nix);
}
// lib.mapAttrs' (name: value: {
  name = "compliance-${name}";
  value = if lib.hasSuffix "eval" name then eval value else vm value;
}) compliance
// lib.mapAttrs' (name: module: {
  name = "pkg-${name}";
  value = vm (runTest (lib.modules.importApply module { inherit serviceModules; }));
}) pkgTests
// {
  pkg-php-fpm = vm (runTest {
    imports = [ (lib.modules.importApply ./packages/php-fpm.nix { inherit serviceModules; }) ];
    _module.args.php = php';
  });
}
