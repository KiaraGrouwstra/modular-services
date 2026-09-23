{
  description = "Modular services: services defined as modules, portable across configuration frameworks.";

  inputs = {
    # The channel tarball rather than the git repository: it is a fraction of
    # the download, and it only advances once Hydra has built the channel, so
    # every derivation this flake evaluates is already in cache.nixos.org.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    # The other configuration frameworks that `integrations/` targets. Only
    # their tests use them. They are sources, not flakes (`flake = false`), so
    # `./default.nix` can fetch each one from `flake.lock` in the same way,
    # and their own inputs do not go into the lock.
    finix = {
      url = "github:finix-community/finix";
      flake = false;
    };
    services-flake = {
      url = "github:juspay/services-flake";
      flake = false;
    };
    # services-flake builds on it, and does not pin it itself.
    process-compose-flake = {
      url = "github:Platonic-Systems/process-compose-flake";
      flake = false;
    };
    devenv = {
      url = "github:cachix/devenv";
      flake = false;
    };
    nixng = {
      url = "github:nix-community/NixNG";
      flake = false;
    };
    nixbsd = {
      url = "github:nixos-bsd/nixbsd";
      flake = false;
    };
    # The nixpkgs that NixBSD locks. NixBSD imports modules from nixpkgs, thus
    # it does not evaluate with any other nixpkgs. Update it with `nixbsd`.
    nixbsd-nixpkgs = {
      url = "https://releases.nixos.org/nixos/unstable-small/nixos-26.11pre1032146.dc29ee8fa098/nixexprs.tar.xz";
      flake = false;
    };
    # NixBSD adds the `mini-tmpfiles` package with the overlay of this flake.
    # The overlay does not use `nixpkgs`. Update it with `nixbsd`.
    nixbsd-mini-tmpfiles = {
      url = "github:nixos-bsd/mini-tmpfiles";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      # ./default.nix is the whole of it. All this adds is what a flake knows
      # and a bare `import` does not: the pin resolved through `flake.lock`
      # rather than re-fetched from it, and the source's revision.
      call =
        args:
        import ./. (
          {
            nixpkgs = nixpkgs.outPath;
            inputs = lib.mapAttrs (_: input: input.outPath) (
              lib.removeAttrs inputs [
                "self"
                "nixpkgs"
              ]
            );
            src = self;
            revision = self.rev or self.dirtyRev or "dirty";
          }
          // args
        );

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # The outputs ./default.nix produces for the one system it was called
      # with. Everything else it produces is system-independent and passes
      # through untouched; `checks.non-flake-consumer` proves that of each.
      perSystem = import ./ci/per-system.nix;
    in
    # `call { }` leaves `system` at its default, which no attribute surviving
    # this `removeAttrs` depends on, so it is never forced.
    lib.removeAttrs (call { }) perSystem
    // lib.genAttrs perSystem (attr: lib.genAttrs systems (system: (call { inherit system; }).${attr}));
}
