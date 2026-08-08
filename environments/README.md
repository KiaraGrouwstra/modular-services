# Adding an environment

An *environment* is one configuration framework's integration of modular
services: NixOS on systemd, Home Manager on systemd user units, `nix-darwin` on
launchd, and so on. Each lives in `environments/<name>/` and is tested
separately.

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

## One environment per framework

The seam is the configuration framework: not the service manager, and not the
privilege level. An environment owns an *evaluation*. `lib.nix` says how to build
a configuration and how to test one; `disable-upstream.nix` says what that
framework already ships that has to give way. Anything that shares those two
answers belongs in the same directory, so `environments/` stays flat -- one
directory per framework, one level deep, with whatever internal structure that
framework needs.

Per-user services on NixOS are the case that makes the rule concrete. Upstream's
in-progress version declares `users.users.<name>.services` as a NixOS module that
siphons into `systemd.user.services`, reusing the same `service.nix` and reading
`config.systemd.package` from the same evaluation as `system.services`. An
`environments/nixos-user/` would restate all four contract files to describe one
evaluation, and would double the NixOS test runs to prove it twice. It is a
second option surface inside `environments/nixos/`, nested under `systemd/` as
`system/` and `user/` the way upstream nests it.

Home Manager is the contrast that shows the seam is not the service manager
either. It also targets systemd user units, and it is still its own environment,
because a Home Manager configuration is evaluated and tested through an entirely
different entry point.

## What an environment does not own

- **The portable layer** (`lib/services/`) is shared and must stay free of
  framework-specific paths and of the `pkgs` module argument. If an environment
  needs something from it, that something belongs in the portable layer for
  everyone.
- **The compliance suite** (`compliance/`) is shared. An environment
  *instantiates* it, supplying `evalConfig`, `mkTest`, `sharedDir` and
  `callReload`, and may add its own manager-specific assertions on top;
  `environments/nixos/tests/compliance.nix` shows both halves.
- **Service modules** (`service-modules/`) are environment-agnostic by
  construction: every one declares `_class = "service"` and none imports
  anything from `lib/services`. An environment that cannot run a given service
  simply does not test it.

## Where to start

Read the `configure` docstring in
[`lib/services/default.nix`](../lib/services/default.nix): it is the
authoritative how-to for the `default.nix` half, with a worked `nix-darwin`
sketch. Then mirror `environments/nixos/` for the other three files.

Home Manager is the intended next environment; it slots in as
`environments/home-manager/` under the same four-file contract. [finix], which
runs finit as pid 1, is the other obvious candidate: it already carries its own
integration, and `service-modules/php/service.nix` keeps upstream's dormant
`lib.optionalAttrs (options ? finit)` branch for exactly that manager.

[finix]: https://github.com/finix-community/finix
