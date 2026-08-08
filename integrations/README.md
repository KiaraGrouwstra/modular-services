# Adding an integration

An *integration* connects modular services to one configuration framework: NixOS
on systemd, Home Manager on systemd user units, `nix-darwin` on launchd, and so
on. Each lives in `integrations/<name>/` and is tested separately.

`integrations/<name>/` is a contract, not a convention. Provide exactly these
four things and the rest of the repository picks the integration up on its own:

| file | contract |
|---|---|
| `default.nix` | The module to import into that configuration system. Declares the services option in terms of `lib.services.configure`, and translates the resulting service tree into whatever the integration's service manager consumes. |
| `disable-upstream.nix` | Eval-time removal of that framework's own in-tree copy of modular services, if it has one. No patching of the input, no fork branch. Imported by `default.nix`. |
| `lib.nix` | `{ evalSystem, runTest, ... }`: how to evaluate a configuration and how to run a VM test *there*. |
| `tests/default.nix` | `{ <name> = { kind = "eval" \| "vm"; drv = <derivation>; }; }`, taking `{ lib, nixpkgs, self, pkgs }`. |

`ci/tests.nix` reads `integrations/` from the filesystem and picks up any
directory containing `tests/default.nix`, exposing its tests as
`<integration>-<test>`. That single hook feeds `checks`, `nix flake check`, and
the GitHub Actions matrix, so an integration that honours the contract needs
**no workflow edits** and no registration anywhere.

`kind` splits the CI matrix: `"eval"` tests build without a virtual machine and
run on any runner; `"vm"` tests need `/dev/kvm`.

## What makes an integration

An integration owns an *evaluation*. `lib.nix` says how to build a configuration
and how to test one; `disable-upstream.nix` says what that framework already
ships that has to give way. Anything that shares those two answers belongs in the
same directory, so `integrations/` stays flat -- one directory per set of
answers, one level deep.

Flat bounds `integrations/` itself, not what an integration contains. The
implementation sits one level down, in a directory named for the service manager
it targets: `integrations/nixos/systemd/`. A framework that grows a second
manager -- NixOS on finit, say -- gets a sibling there rather than a second
integration, since it shares both answers, and `integrations/nixos/default.nix`
is where the choice between them is made.

The rule is about those two answers rather than about an axis, because the axes
are not knowable up front. Three are visible already and they do not nest: the
configuration framework, the service manager an evaluation targets, and the
privilege level of the unit that comes out.

Whether a permutation is then a second integration, a second implementation
inside this one, or a variant key is worth deciding against something that runs.
Four small files per integration is what keeps that decision cheap to revisit.

Two in-progress upstream changes show the rule applied, and it lands on opposite
sides of them.

The first declares `users.users.<name>.services` as a NixOS module siphoning into
`systemd.user.services`, reusing the same `service.nix` and reading
`config.systemd.package` from the same evaluation as `system.services`. An
`integrations/nixos-user/` would restate all four contract files to describe one
evaluation, and would double the NixOS test runs to prove it twice. It is a
second option surface inside `integrations/nixos/`, nested under `systemd/` as
`system/` and `user/` the way upstream nests it.

The second splits each service module in two: a pure half, and a variant holding
what only holds in one place -- `DynamicUser`, `AmbientCapabilities`,
`wantedBy = [ "multi-user.target" ]` -- enumerated in a registry keyed
`<variant>.<pkg>.<service>`, with `system` today and `user` expected beside it.
Upstream calls that first key an environment; by the rule above it is not an
integration, because it selects a service module rather than an evaluation, and
it selects along the privilege level of a systemd unit, which cuts *across*
frameworks. Home Manager emits systemd user units too, so a `user` variant is one
both it and NixOS want. An `integrations/nixos-user/` would bury it in one
framework's directory, for the other to reach into.

Variants therefore belong beside the services they vary, in
`modular-services/`, and an integration owns the *registry*: which variant key
it consumes, and which services it claims to support there. Upstream keeps its
registry under `nixos/modules/`, having one integration to serve; that placement
is the one part of its shape that does not carry over.

Home Manager decides the other way on the same reasoning. It also targets systemd
user units, and it is still its own integration, because a Home Manager
configuration is evaluated and tested through an entirely different entry point.

## What an integration does not own

- **The portable layer** (`lib/services/`) is shared and must stay free of
  framework-specific paths and of the `pkgs` module argument. If an integration
  needs something from it, that something belongs in the portable layer for
  everyone.
- **The compliance suite** (`compliance/`) is shared. An integration
  *instantiates* it, supplying `evalConfig`, `mkTest`, `sharedDir` and
  `callReload`, and may add its own manager-specific assertions on top;
  `integrations/nixos/tests/compliance.nix` shows both halves.
- **The services** (`modular-services/`) are shared: every one declares
  `_class = "service"` and none imports anything from `lib/services`. A service
  that needs settings holding at only one privilege level gets a variant beside
  the pure module, not a copy inside an integration; see "What makes an
  integration" above. An integration that cannot run a given service simply does
  not test it.

## Where to start

Read the `configure` docstring in
[`lib/services/default.nix`](../lib/services/default.nix): it is the
authoritative how-to for the `default.nix` half, with a worked `nix-darwin`
sketch. Then mirror `integrations/nixos/` for the other three files.

Home Manager is the intended next integration; it slots in as
`integrations/home-manager/` under the same four-file contract. [finix], which
runs finit as pid 1, is the other obvious candidate: it already carries its own
integration, and `modular-services/php/service.nix` keeps upstream's dormant
`lib.optionalAttrs (options ? finit)` branch for exactly that manager.

[finix]: https://github.com/finix-community/finix
