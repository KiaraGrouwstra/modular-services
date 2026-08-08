# modular-services

Services defined **as** modules rather than **in** modules, portable across
configuration frameworks.

A conventional NixOS service is a module that writes into `systemd.services.*`.
A modular service is a module that *is* the service: it declares its own
options, its own processes, and its own config files, and knows nothing about
the system it will run on. A framework integration -- an *environment* -- turns
that description into whatever its service manager consumes.

The subsystem lives in nixpkgs as of NixOS 25.11, still marked in development.
This repository carries the canonical copy so it can move at its own pace, be
consumed by NixOS, Home Manager and `nix-darwin` alike, and grow per-environment
test coverage that the nixpkgs tree cannot host. Everything here came from
nixpkgs; [`PROVENANCE.md`](./PROVENANCE.md) records what, from where, and what
changed.

## Using it

Add the flake and import `nixosModules.default`. That module brings in this
repository's implementation *and* disables the nixpkgs copy, so the two cannot
both be live:

```nix
{
  inputs.modular-services.url = "github:kiara-grouwstra/modular-services";

  outputs =
    { nixpkgs, modular-services, ... }:
    {
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

`serviceModules.<pkg> pkgs` is the canonical way to consume a service. See
[`doc/modular-services.md`](./doc/modular-services.md) for the manual chapter and
[`doc/writing-and-reviewing.md`](./doc/writing-and-reviewing.md) for how to write
one.

Nothing forces you to pin the same nixpkgs this flake does: `nixosModules.default`
disables the in-tree copy by *relative* module key, so it matches whichever
nixpkgs the consumer evaluates against.

### Without flakes

Flakes are not required, and not the source of truth.
[`default.nix`](./default.nix) holds the entire consumer surface and takes a
`lib` from the caller; `flake.nix` imports it and adds the per-system outputs.
Fetch the source however you like -- `npins`, `fetchTarball`, a subtree -- and
call it:

```nix
{ pkgs, ... }:
let
  modular-services = import sources.modular-services { inherit (pkgs) lib; };
in
{
  imports = [ modular-services.nixosModules.default ];
  system.services.tlshd.imports = [ (modular-services.serviceModules.ktls-utils pkgs) ];
}
```

The two are kept in step by `checks.non-flake-consumer`, which evaluates a NixOS
system from `default.nix` alone and fails if the flake exposes a consumer
attribute that `default.nix` does not. This repository's own nixpkgs pin is
never in the picture either way: the NixOS module takes `lib` and `pkgs` from
the configuration importing it, so consuming this repository never pulls in a
second nixpkgs.

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
`serviceModules.<pkg> pkgs`, which is what every test here does, or apply
`overlays.packageServices` if you have existing code written against the
`passthru` path. That overlay excludes `php`, which regenerates its own
`passthru` and cannot be overridden this way.

## Outputs

Everything above the rule comes from [`default.nix`](./default.nix) and is
available with or without flakes; everything below it is flake-only, being
per-system.

| output | what |
|---|---|
| `serviceModules.<pkg>` | `pkgs -> module`, to import into `system.services.<name>`. |
| `nixosModules.default` | The disable plus this repository's implementation. |
| `nixosModules.modularServices` | Just the implementation. |
| `nixosModules.disableUpstream` | Just the disable. |
| `nixosModules.documentation` | Replacement option-documentation registry. |
| `lib.servicesFor` | The portable layer against a caller-supplied `lib`; the entry point for a new environment. |
| `lib.services` | `lib.servicesFor` against this flake's nixpkgs. |
| `lib.mkComplianceSuite` | The environment-agnostic compliance suite, for a package set. |
| `overlays.default` | Adds `pkgs.modularServices.*`. Overrides nothing, so no rebuilds. |
| `overlays.packageServices` | Opt-in; repoints `pkgs.<pkg>.services.*` here. |
| --- | --- |
| `checks.<system>.*` | Every test, environment and repo-level alike. |
| `packages.<system>.docs` | The manual chapter as HTML. |
| `ci.<system>.matrix` | Consumed only by the GitHub Actions workflow. |

## Layout

| directory | what |
|---|---|
| `lib/services/` | The portable layer. No nixpkgs paths, no `pkgs` module argument. |
| `compliance/` | The environment-agnostic compliance suite each environment instantiates. |
| `environments/` | One directory per configuration framework. See [`environments/README.md`](./environments/README.md). |
| `service-modules/` | The per-package service modules, `_class = "service"` and environment-agnostic. |
| `doc/` | The manual chapter, and the list of services whose options it documents. One book about the subsystem, not one per environment; each environment renders that list its own way. |
| `overlays/`, `ci/` | Overlays, and the test/matrix wiring. |
| `default.nix`, `flake.nix` | The consumer surface, and the flake wrapper adding per-system outputs to it. |

Adding an environment means adding `environments/<name>/` with four files;
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

VM tests need `/dev/kvm`, and `kvm` in `nix config show system-features`. Run
them a few at a time: `checks.nixos-pkg-ghostunnel` starts its service at boot
and only recovers, through `Restart=always`, once the test script has copied the
certificates in, so on a host running many virtual machines at once the first
request can arrive before the service is up. CI gives each test its own job and
does not hit this.

### CI setup

`ci.yml` runs on every push and pull request, against the pinned `flake.lock`,
so a run is reproducible and a red result means this repository changed.
[Dependabot](./.github/dependabot.yml) moves the pin, weekly, as a pull request:
the suite runs against the new nixpkgs there, and a break upstream shows up as a
red pull request rather than a red `main`. It updates the action versions in the
workflow the same way.

One optional repository secret, `CACHIX_AUTH_TOKEN`: create a cache named
`modular-services` at [cachix.org](https://cachix.org) and take a write token
from its Settings tab. Without it CI still runs, just without a cache. Pull
requests set `skipPush`, so forks -- and Dependabot, which never receives
repository secrets -- build read-only rather than failing.

Expect modest gains from that cache. The `nixos-unstable` pin means everything
from nixpkgs comes out of `cache.nixos.org` already, so it only ever holds this
repository's own derivations: the rendered manual, and one small result per VM
test. Its value is skipping a test that has not changed, not avoiding rebuilds
of nixpkgs. `nix-community/cache-nix-action` does the same job through the
GitHub Actions cache with no external account, at the cost of a 10 GB
per-repository ceiling that VM test closures can reach.

## Licence

MIT, as nixpkgs, Home Manager, `nix-darwin` and finix all are, so code moves into
this repository and back out to any of them without a relicensing step.
Contributions are taken under the same terms. See [`LICENSE`](./LICENSE) and the
licensing section of [`PROVENANCE.md`](./PROVENANCE.md#licensing).
