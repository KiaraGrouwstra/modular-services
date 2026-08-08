# Adding an environment

An *environment* is one integration of modular services: NixOS on systemd, Home
Manager on systemd user units, `nix-darwin` on launchd, and so on. Each lives in
`environments/<name>/` and is tested separately.

`environments/<name>/` is a contract, not a convention. Provide exactly these
four things and the rest of the repository picks the environment up on its own:

| file | contract |
|---|---|
| `default.nix` | The module to import into that configuration system. Declares the services option in terms of `lib.services.configure`, and translates the resulting service tree into whatever the environment's service manager consumes. |
| `disable-upstream.nix` | Eval-time removal of that framework's own in-tree copy of modular services, if it has one. No patching of the input, no fork branch. Imported by `default.nix`. |
| `lib.nix` | `{ evalSystem, runTest, ... }`: how to evaluate a configuration and how to run a VM test *there*. |
| `tests/default.nix` | `{ <name> = { kind = "eval" \| "vm"; drv = <derivation>; }; }`, taking `{ lib, nixpkgs, self, pkgs }`. |

`ci/tests.nix` reads `environments/` from the filesystem and picks up any
directory containing `tests/default.nix`, exposing its tests as
`<env>-<test>`. That single hook feeds `checks`, `nix flake check`, and the
GitHub Actions matrix, so an environment that honours the contract needs **no
workflow edits** and no registration anywhere.

`kind` splits the CI matrix: `"eval"` tests build without a virtual machine and
run on any runner; `"vm"` tests need `/dev/kvm`.

## What makes an environment

An environment owns an *evaluation*. `lib.nix` says how to build a configuration
and how to test one; `disable-upstream.nix` says what that framework already
ships that has to give way. Anything that shares those two answers belongs in the
same directory, so `environments/` stays flat -- one directory per set of
answers, one level deep.

Flat bounds `environments/` itself, not what an environment contains. The
implementation sits one level down, in a directory named for the service manager
it targets: `environments/nixos/systemd/`. A framework that grows a second
manager -- NixOS on finit, say -- gets a sibling there rather than a second
environment, since it shares both answers, and `environments/nixos/default.nix`
is where the choice between them is made.

The rule is about those two answers rather than about an axis, because the axes
are not knowable up front. Three are visible already and they do not nest: the
configuration framework, the service manager an evaluation targets, and the
privilege level of the unit that comes out.

Whether a permutation is then a second environment, a second implementation
inside this one, or a variant key is worth deciding against something that runs.
Four small files per environment is what keeps that decision cheap to revisit.

Two in-progress upstream changes show the rule applied, and it lands on opposite
sides of them.

The first declares `users.users.<name>.services` as a NixOS module siphoning into
`systemd.user.services`, reusing the same `service.nix` and reading
`config.systemd.package` from the same evaluation as `system.services`. An
`environments/nixos-user/` would restate all four contract files to describe one
evaluation, and would double the NixOS test runs to prove it twice. It is a
second option surface inside `environments/nixos/`, nested under `systemd/` as
`system/` and `user/` the way upstream nests it.

The second splits each service module in two: a pure half, and a variant holding
what only holds in one place -- `DynamicUser`, `AmbientCapabilities`,
`wantedBy = [ "multi-user.target" ]` -- enumerated in a registry keyed
`<variant>.<pkg>.<service>`, with `system` today and `user` expected beside it.
That registry calls its first key an environment, and by the rule above it is not
one: it selects a service module rather than an evaluation, and it selects along
the privilege level of a systemd unit, which cuts *across* frameworks. Home
Manager emits systemd user units too, so a `user` variant is one both it and
NixOS want. An `environments/nixos-user/` would bury it in one framework's
directory, for the other to reach into.

Variants therefore belong beside the services they vary, in
`modular-services/`, and an environment owns the *registry*: which variant key it
consumes, and which services it claims to support there. Upstream keeps its
registry under `nixos/modules/`, having one environment to serve; that placement
is the one part of its shape that does not carry over.

Home Manager decides the other way on the same reasoning. It also targets systemd
user units, and it is still its own environment, because a Home Manager
configuration is evaluated and tested through an entirely different entry point.

## What an environment does not own

- **The portable layer** (`lib/services/`) is shared and must stay free of
  framework-specific paths and of the `pkgs` module argument. If an environment
  needs something from it, that something belongs in the portable layer for
  everyone.
- **The compliance suite** (`compliance/`) is shared. An environment
  *instantiates* it, supplying `evalConfig`, `mkTest`, `sharedDir` and
  `callReload`, and may add its own manager-specific assertions on top;
  `environments/nixos/tests/compliance.nix` shows both halves.
- **The services** (`modular-services/`) are shared: every one declares
  `_class = "service"` and none imports anything from `lib/services`. A service
  that needs settings holding at only one privilege level gets a variant beside
  the pure module, not a copy inside an environment; see "What makes an
  environment" above. An environment that cannot run a given service simply does
  not test it.

## Where to start

Read the `configure` docstring in
[`lib/services/default.nix`](../lib/services/default.nix): it is the
authoritative how-to for the `default.nix` half, with a worked `nix-darwin`
sketch. Then mirror `environments/nixos/` for the other three files.

Home Manager is the intended next environment; it slots in as
`environments/home-manager/` under the same four-file contract. [finix], which
runs finit as pid 1, is the other obvious candidate: it already carries its own
integration, and `modular-services/php/service.nix` keeps upstream's dormant
`lib.optionalAttrs (options ? finit)` branch for exactly that manager.

[finix]: https://github.com/finix-community/finix
