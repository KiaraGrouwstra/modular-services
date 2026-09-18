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
| `modular/` | The NixOS variant of each service: what `modular-services/` cannot say because it is not systemd. Registered as `config.modularServices.<pkg>.<svc>`. |
| `documentation.nix` | Renders `doc/registry.nix` into `documentation.nixos.extraModules` (`nixosModules.documentation`), replacing the upstream registry the disable removes. |
| `lib.nix` | `evalModules` / `evalSystem` / `runTest`, reproducing what `nixos/tests/all-tests.nix` gives in-tree tests. |
| `tests/` | The integration's test set. |

`systemd/` splits into `system/` and `user/`, one per systemd manager instance.
Per-user services are `users.users.<name>.services`, in this same evaluation
rather than as a second integration; [`../README.md`](../README.md) explains what
makes an integration.

## Per-user services

`users.users.<name>.services` is the same service submodule as
`system.services`, evaluated once per user so that the `configData` paths can be
baked in. The integration sets `defaultWantedBy` to `default.target`, the target
of a per-user systemd instance, where the system integration sets
`multi-user.target`. A service reaches systemd twice over.

A user reaches their services through a `user-services-<name>` package added to
`users.users.<name>.packages`. That package carries
`share/systemd/user/<service>.service` and, for each target the unit wants,
`share/systemd/user/<target>.wants/<service>.service`. A user's systemd
instance finds these through `$XDG_DATA_DIRS`. The name there is the short one,
so a user sees `hello.service`.

`configData` follows the same profile: paths are
`/etc/profiles/per-user/<name>/etc/xdg/user-services/<service>/<file>`, which is
in `$XDG_CONFIG_DIRS`, and the entries are symlinked into the same package
rather than into `environment.etc`.

### Why the units are not in `/etc/systemd/user`

`systemd.user.units` writes `/etc/systemd/user`, which the systemd instance of
every user reads. A unit put there is systemd-wide even when one user alone is
meant to have it. Three things follow. It needs a `<user>--` prefix, because two
users may both have a `hello` service. That prefix is visible to everybody, so
each user's `systemctl --user list-unit-files` lists every other user's
services. And any user may start `<other>--<service>`: it then runs in the
caller's own instance and under the caller's own account, on the caller's own
copy of the `configData`.

The unit files go in the profile of their user instead, where
`/etc/profiles/per-user/<name>/share/systemd/user` is in that user's
`$XDG_DATA_DIRS` and in no other's. The integration renders them with the same
`systemdUtils` helpers that NixOS uses for its own units. The cost is that these
units are not in `systemd.user.services`, thus options and tools that read that
option do not find them.

## Service variants

A module under [`../../modular-services/`](../../modular-services) says what a
service is. It names no service manager, so it cannot say that `tlshd` wants
`remote-fs.target` or runs as a `DynamicUser`. That half lives here, in
[`modular/<pkg>/<svc>/`](./modular): `default.nix` imports the service itself out
of `modularServices.<pkg>`, and `system.nix` adds the systemd definitions.

[`modular/default.nix`](./modular/default.nix) registers the pairs, and
[`systemd/defaults.nix`](./systemd/defaults.nix) makes that registry the default
of `config.modularServices.<pkg>.<svc>` -- so a configuration can substitute its
own variant, and a test reaches the same one a real system gets.

The registry holds *paths*, not `import`s of paths. An `import` yields a bare
function, which carries no `_file`, so the variant's own file drops out of
anything keyed on where a definition came from: `meta.maintainers`, option
attribution, error messages. `checks.nixos-modular-variants` asserts that it
does not.

## Usage

```nix
{
  inputs.modular-services.url = "github:.../modular-services";

  outputs = { nixpkgs, modular-services, ... }: {
    nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
      modules = [
        modular-services.nixosModules.default
        (
          { config, ... }:
          {
            system.services.tlshd.imports = [ config.modularServices.ktls-utils.default ];
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
{ config, pkgs, ... }:
let
  modular-services = import src { inherit (pkgs) lib; };
in
{
  imports = [ modular-services.nixosModules.default ];
  system.services.tlshd.imports = [ config.modularServices.ktls-utils.default ];
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
`config.modularServices.<pkg>.<svc>`, which is what every test here does, or
apply `overlays.passthruServices` if you have existing code written against the
`passthru` path.
