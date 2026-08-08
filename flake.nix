{
  description = "Modular services: services defined as modules, portable across environments using Nix modules.";

  inputs = {
    # The channel tarball rather than the git repository: it is a fraction of
    # the download, and it only advances once Hydra has built the channel, so
    # every derivation this flake evaluates is already in cache.nixos.org.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { self, nixpkgs }:
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
