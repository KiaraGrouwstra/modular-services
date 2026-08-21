# The NixOS integration

Modular services on systemd, for NixOS. This is the canonical copy: nixpkgs
still carries the same code under `nixos/modules/system/service/systemd/`, and
[`disable-upstream.nix`](./disable-upstream.nix) removes it from the evaluation
so the two cannot both be live.

## Layout

| file | role |
|---|---|
| `default.nix` | What a NixOS configuration imports (`nixosModules.default`): the disable plus the implementation. |
| `disable-upstream.nix` | `disabledModules` for the in-tree copy (`nixosModules.disableUpstream`). |
| `systemd/` | The systemd implementation (`nixosModules.systemServices`): `system.services`, the systemd unit options, and `configData` paths. One directory per service manager, so a second would sit beside it. |
| `documentation.nix` | Renders `doc/registry.nix` into `documentation.nixos.extraModules` (`nixosModules.documentation`), replacing the upstream registry the disable removes. |
| `lib.nix` | `evalModules` / `evalSystem` / `runTest`, reproducing what `nixos/tests/all-tests.nix` gives in-tree tests. |
| `tests/` | The integration's test set. |

`systemd/user.nix` is a stub, here as upstream. Per-user services arrive as
`users.users.<name>.services` in this same evaluation rather than as a second
integration; [`../README.md`](../README.md) explains what makes an integration.

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
            system.services.tlshd.imports = [ (modular-services.modularServices.ktls-utils pkgs) ];
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
  system.services.tlshd.imports = [ (modular-services.modularServices.ktls-utils pkgs) ];
}
```

## Applying `configData` changes

A `configData` entry becomes an `environment.etc` file, so a change to one is
part of the system closure and is on disk the moment a configuration is
activated. Whether the running service is told about it is
`applyConfigDataChanges`, which the portable layer declares next to `configData`
itself: "this service picks up configuration changes on its own" is a property
of the program, not of the service manager. It is a `bool` rather than a
reload-or-restart enum, so it says only *whether* changes should be applied and
leaves *how* to the service manager. A single noisy file opts out on its own
through `configData.<name>.applyChanges`, which defaults to `null` and so
inherits the service-level setting.

Here, *how* is a trigger on the service's primary unit: `reloadTriggers` when
the unit declares an `ExecReload`, and `restartTriggers` when it does not.
`switch-to-configuration-ng` does not fall back from reload to restart --
`X-Reload-Triggers` on a unit without `ExecReload=` makes activation exit with
code 4 -- so the choice is made when the unit is generated. Sub-services get
their triggers from their own `configData`, not from the parent's.

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
`modularServices.<pkg> pkgs`, which is what every test here does, or apply
`overlays.passthruServices` if you have existing code written against the
`passthru` path.
