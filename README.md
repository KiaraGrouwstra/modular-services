# modular-services

Services defined **as** modules rather than **in** modules, portable across
configuration frameworks.

A conventional NixOS service is a module that writes into `systemd.services.*`.
A modular service is a module that *is* the service: it declares its own
options, its own processes, and its own config files, and knows nothing about
the system it will run on. A framework *integration* turns that description
into whatever its service manager consumes.

The subsystem lives in nixpkgs as of NixOS 25.11, still marked in development.
This repository carries the canonical copy so it can move at its own pace, be
consumed by NixOS, Home Manager and `nix-darwin` alike, and grow per-integration
test coverage that the nixpkgs tree cannot host. Everything here came from
nixpkgs; [`PROVENANCE.md`](./PROVENANCE.md) records what, from where, and what
changed.

## Using it

Add the flake and import `nixosModules.default`. That module brings in this
repository's implementation *and* disables the nixpkgs copy, so the two cannot
both be live:

```nix
{
  inputs.modular-services.url = "github:kiaragrouwstra/modular-services";

  outputs =
    { nixpkgs, modular-services, ... }:
    {
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

`modularServices.<pkg> pkgs` is the canonical way to consume a service. See
[`doc/modular-services.md`](./doc/modular-services.md) for the manual chapter and
[`doc/writing-and-reviewing.md`](./doc/writing-and-reviewing.md) for how to write
one.

Nothing forces you to pin the same nixpkgs this flake does: `nixosModules.default`
disables the in-tree copy by *relative* module key, so it matches whichever
nixpkgs the consumer evaluates against.

### Without flakes

Flakes are not required, and not the source of truth.
[`default.nix`](./default.nix) produces every output below;
[`flake.nix`](./flake.nix) pins nixpkgs through `flake.lock`, maps the
per-system outputs over the systems this repository supports, and adds nothing
of its own. Fetch the source however you like -- `npins`, `fetchTarball`, a
subtree -- and call it:

```nix
{ pkgs, ... }:
let
  modular-services = import sources.modular-services { inherit (pkgs) lib; };
in
{
  imports = [ modular-services.nixosModules.default ];
  system.services.tlshd.imports = [ (modular-services.modularServices.ktls-utils pkgs) ];
}
```

Every argument is lazy, so a call like that one never evaluates this
repository's nixpkgs pin: the NixOS module takes `lib` and `pkgs` from the
configuration importing it, and consuming this repository pulls in no second
nixpkgs. Passing nothing at all -- `import ./. { }` -- instead resolves the pin
out of `flake.lock` with `fetchTarball` and gives the development outputs as
well, `nix-build default.nix -A checks.nixos-disable-proof` included.

`checks.non-flake-consumer` keeps the two honest: it evaluates a NixOS system
from `default.nix` alone, and it evaluates every output outside
[`ci/per-system.nix`](./ci/per-system.nix) with the system, the package set and
the pin all replaced by `throw`, so anything that quietly needs one of them
fails there rather than in a consumer's evaluation.

### Known residue

Two things survive the disable. Both are documented rather than fixed, because
fixing either would mean patching the nixpkgs input, which this design refuses
to do.

**Option documentation.** `nixos/modules/misc/documentation.nix` computes its
module list from the raw `baseModules`, before `disabledModules` is applied. With
`documentation.nixos.enable = true` a system therefore still *renders* upstream's
`system.services` documentation, even though evaluation behaviour is entirely
this repository's. Import `nixosModules.documentation` for the corrected
registry, which also covers the two service modules the nixpkgs registry is
missing.

**`pkgs.<pkg>.services.default`.** Package `passthru` is untouched, so that
attribute still resolves to the service module vendored in nixpkgs. Use
`modularServices.<pkg> pkgs`, which is what every test here does, or apply
`overlays.passthruServices` if you have existing code written against the
`passthru` path. That overlay excludes `php`, which regenerates its own
`passthru` and cannot be overridden this way.

## Outputs

All of them come from [`default.nix`](./default.nix), and what each one is for
is written down once, in [`doc/outputs.nix`](./doc/outputs.nix). The manual's
*Flake attributes* chapter renders that alongside the lists it can generate --
every service module, and every check with its `kind` and `integration` --
and `checks.docs-outputs-complete` fails if an output arrives undescribed or a
description outlives its output.

Everything named in [`ci/per-system.nix`](./ci/per-system.nix) is produced for
the system `default.nix` was called with, which is the group a flake keys as
`checks.<system>`, `packages.<system>` and so on; the rest are the same
whatever the system, and a flake publishes them unkeyed.

## Layout

| directory | what |
|---|---|
| `lib/services/` | The portable layer. No nixpkgs paths, no `pkgs` module argument. |
| `compliance/` | The integration-agnostic compliance suite each integration instantiates. |
| `integrations/` | One directory per integration. See [`integrations/README.md`](./integrations/README.md). |
| `modular-services/` | The services themselves: `_class = "service"`, integration-agnostic, one directory per providing package. |
| `doc/` | The manual: its hand-written chapters, and the lists its generated ones render -- the services whose options it documents, and what each output is for. One book about the subsystem, not one per integration; each integration renders the service list its own way. |
| `overlays/`, `ci/` | Overlays, and the test/matrix wiring. |
| `default.nix`, `flake.nix` | Every output, and the flake wrapper that keys the per-system ones by system. |

Adding an integration means adding `integrations/<name>/` with four files;
`ci/tests.nix` discovers it from the filesystem, so `checks`, `nix flake check`
and CI pick it up with no registration anywhere. Home Manager is the intended
next one.

## Development

```bash
nix flake check --no-build -L   # evaluate every output, instantiate every check
nix fmt                         # nixfmt, via treefmt
nix build -L .#checks.x86_64-linux.nixos-disable-proof   # the check the design rests on
nix flake check -L              # everything, including the VM tests
```

The same without flakes, resolving the pin out of `flake.lock`:

```bash
nix-build default.nix -A checks.nixos-disable-proof
nix-instantiate default.nix -A checks   # instantiate every check, build none
```

VM tests need `/dev/kvm`, and `kvm` in `nix config show system-features`.
`checks.nixos-pkg-php-fpm` runs in a `systemd-nspawn` container rather than a
virtual machine, and additionally wants `auto-allocate-uids` and the
`uid-range` system feature; `nixos/doc/manual/development/running-nixos-tests.section.md`
in nixpkgs lists the settings. Run them a few at a time: `checks.nixos-pkg-ghostunnel` starts its service at boot
and only recovers, through `Restart=always`, once the test script has copied the
certificates in, so on a host running many virtual machines at once the first
request can arrive before the service is up. CI gives each test its own job and
does not hit this.

### Binary cache

CI pushes what it builds on `main` to a public cache, so a VM test that has not
changed since the last green run downloads instead of booting:

```
https://modular-services.cachix.org
modular-services.cachix.org-1:SCCVjjlFpkNBm9YQS+rePVeK/nhc9kXA/6PC8gql4XQ=
```

Declaratively, on the machine you develop from:

```nix
{
  nix.settings = {
    substituters = [ "https://modular-services.cachix.org" ];
    trusted-public-keys = [
      "modular-services.cachix.org-1:SCCVjjlFpkNBm9YQS+rePVeK/nhc9kXA/6PC8gql4XQ="
    ];
  };
}
```

For one command, without configuring anything:

```bash
nix flake check -L \
  --extra-substituters https://modular-services.cachix.org \
  --extra-trusted-public-keys modular-services.cachix.org-1:SCCVjjlFpkNBm9YQS+rePVeK/nhc9kXA/6PC8gql4XQ=
```

Nix ignores both flags unless you are a trusted user, so on a multi-user daemon
install the settings have to come from the daemon's configuration rather than
the command line.

The cache is for working *on* this repository, not for consuming it. Everything
here evaluates to modules, so a configuration that imports
`nixosModules.default` builds nothing from this repository and gains nothing
from the cache; it holds test results and the rendered manual. Pull requests
build read-only against it, and `flake.nix` sets no `nixConfig`, so nothing
about consuming this flake changes if you skip this section entirely.

### CI setup

`ci.yml` runs on every push and pull request, against the pinned `flake.lock`,
so a run is reproducible and a red result means this repository changed.
[Dependabot](./.github/dependabot.yml) moves the pin, weekly, as a pull request:
the suite runs against the new nixpkgs there, and a break upstream shows up as a
red pull request rather than a red `main`. It updates the action versions in the
workflow the same way.

One optional repository secret, `CACHIX_AUTH_TOKEN`, holds a write token for
the cache above, taken from its Settings tab at
[cachix.org](https://cachix.org). A fork that wants its own creates a cache
there and sets the same secret. Without the secret CI still runs, just without
pushing. Pull requests set `skipPush`, so forks -- and Dependabot, which never
receives repository secrets -- build read-only rather than failing.

Gains are modest by construction. The `nixos-unstable` pin means everything
from nixpkgs comes out of `cache.nixos.org` already, so the cache only ever
holds this repository's own derivations. Its value is skipping a test that has
not changed, not avoiding rebuilds of nixpkgs. `nix-community/cache-nix-action`
does the same job through the
GitHub Actions cache with no external account, at the cost of a 10 GB
per-repository ceiling that VM test closures can reach.

## Licence

MIT, as nixpkgs, Home Manager, `nix-darwin` and finix all are, so code moves into
this repository and back out to any of them without a relicensing step.
Contributions are taken under the same terms. See [`LICENSE`](./LICENSE) and the
licensing section of [`PROVENANCE.md`](./PROVENANCE.md#licensing).
