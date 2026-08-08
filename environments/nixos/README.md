# The NixOS environment

Modular services on systemd, for NixOS. This is the canonical copy: nixpkgs
still carries the same code under `nixos/modules/system/service/systemd/`, and
[`disable-upstream.nix`](./disable-upstream.nix) removes it from the evaluation
so the two cannot both be live.

## Layout

| file | role |
|---|---|
| `default.nix` | What a NixOS configuration imports (`nixosModules.default`): the disable plus the implementation. |
| `disable-upstream.nix` | `disabledModules` for the in-tree copy (`nixosModules.disableUpstream`). |
| `systemd/` | The implementation (`nixosModules.modularServices`): `system.services`, the systemd unit options, and `configData` paths. |
| `documentation.nix` | Renders `doc/registry.nix` into `documentation.nixos.extraModules` (`nixosModules.documentation`), replacing the upstream registry the disable removes. |
| `lib.nix` | `evalModules` / `evalSystem` / `runTest`, reproducing what `nixos/tests/all-tests.nix` gives in-tree tests. |
| `tests/` | The environment's test set. |

`systemd/user.nix` is a stub, here as upstream. Per-user services arrive as
`users.users.<name>.services` in this same evaluation rather than as a second
environment; [`../README.md`](../README.md) explains why the seam falls there.

## Usage

```nix
{
  inputs.modular-services.url = "github:.../modular-services";

  outputs = { nixpkgs, modular-services, ... }: {
    nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
      modules = [
        modular-services.nixosModules.default
        (
          { pkgs, ... }:
          {
            system.services.tlshd.imports = [ (modular-services.serviceModules.ktls-utils pkgs) ];
          }
        )
      ];
    };
  };
}
```

Without flakes, the same thing from [`../../default.nix`](../../default.nix),
with `src` however you fetched this repository:

```nix
{ pkgs, ... }:
let
  modular-services = import src { inherit (pkgs) lib; };
in
{
  imports = [ modular-services.nixosModules.default ];
  system.services.tlshd.imports = [ (modular-services.serviceModules.ktls-utils pkgs) ];
}
```

## Known residue

Two things survive the disable. Both are documented rather than fixed, because
fixing either would mean patching the nixpkgs input.

**Option documentation.** `nixos/modules/misc/documentation.nix` computes
`docModules` from the raw `baseModules`, before `disabledModules` is applied.
With `documentation.nixos.enable = true`, a NixOS system therefore still
*renders* upstream's `system.services` documentation, even though evaluation
behaviour is entirely ours. Import `nixosModules.documentation` for this
repository's corrected registry. VM tests are unaffected:
`nixos/lib/testing/nixos-test-base.nix` sets `documentation.nixos.enable` to
false.

**`pkgs.<pkg>.services.default`.** Package `passthru` is untouched, so that
attribute still resolves to the service module vendored in nixpkgs. Use
`serviceModules.<pkg> pkgs`, which is what every test here does, or apply
`overlays.packageServices` if you have existing code written against the
`passthru` path.
