# Provenance

Everything in this repository that came from [nixpkgs] is listed below, with
where it came from and whether it was changed. This table is the substantive
attribution required by the MIT licence in [`LICENSE`](./LICENSE), which carries
both the nixpkgs copyright line and this project's.

Keeping it current is a review responsibility, not an automated one. The same
people maintain this subsystem here and in nixpkgs, so a change on either side
is known on both; a checked-in diff against upstream would report churn its
author had already seen, and would constrain this table to a shape a parser can
read. `checks.disable-keys-exist` covers the one case that *is* silent:
`disabledModules` ignores a key matching nothing, so an upstream rename would
turn [`integrations/nixos/disable-upstream.nix`](./integrations/nixos/disable-upstream.nix)
into a no-op without any error.

## Licensing

MIT throughout, which is what makes carrying code in both directions
unremarkable. Every project this repository draws on, or expects to feed back
into, ships the same licence text: [nixpkgs], [Home Manager], [`nix-darwin`] and
[finix] are all MIT, and none of them asks a contributor to sign anything on top.
Code that arrives here from one of them, or leaves here for one of them, is MIT
at both ends, with no relicensing step for anyone to get wrong.

Two rules keep it that way.

**Contributions here are MIT.** Opening a pull request against this repository
offers the change under [`LICENSE`](./LICENSE). A patch that cannot be offered on
those terms cannot be taken, however good it is: it would strand whatever it
touched, since that file could then never go upstream.

**Vendoring from a new project adds that project's copyright line** to `LICENSE`,
above the permission notice, and its files to the table below. One permission
notice over several copyright lines is the ordinary shape for a derived work, and
it is the whole of what MIT asks as long as the licence text itself is identical
across the sources -- which, so far, it is.

The case to plan for is an upstream that is *not* MIT. [NixNG] is MPL-2.0, which
is copyleft per file: its code cannot be folded into an MIT file, so an
integration built on it would need its own directory and its own `LICENSE`
rather than another line in this one. Nothing here is in that position today.

## No per-file provenance headers

Vendored files carry **no** added header comment. That is deliberate: keeping
them byte-identical to upstream makes a plain `diff` against a nixpkgs checkout
a usable answer to "what did we change", and a header would defeat it on every
single file. The files that genuinely had to change are marked `modified` below
with the reason; those are the only places where a divergence exists at all.

No `SPDX-License-Identifier` line either. Those earn their keep when files in one
tree carry different licences; here every file is MIT under the same notice, so a
header per file would restate `LICENSE` 53 times and still not say which upstream
the file came from -- which is the question this table answers.

No per-row revision either. [`flake.lock`](./flake.lock) records the pin, and a
second copy per row would only be another thing to keep in step, touching all 39
rows on every re-vendor. Note that the pin is the `nixos-unstable` channel, which
advances only once Hydra has built it and so trails the nixpkgs default branch by
a few days: a file vendored from the branch can be *newer* than its counterpart
in the pinned nixpkgs.

## The table

| repo path | nixpkgs path | state | reason |
|---|---|---|---|
| `lib/services/default.nix` | `lib/services/lib.nix` | modified | Renamed to `default.nix` so `import ./lib/services` resolves. The `configure` docstring is retargeted from a `nix-darwin` sketch to the `integrations/<name>/` contract, which makes it the how-to-add-an-integration guide. Names `importService` from the portable layer itself, where upstream adds `lib.importService` to the nixpkgs `lib`. |
| `lib/services/service.nix` | `lib/services/service.nix` | modified | The two out-of-tree imports point at `./vendor/` instead of `../modules/generic/`. |
| `lib/services/config-data.nix` | `lib/services/config-data.nix` | modified | Test-path comment retargeted to `integrations/nixos/tests/etc/test.nix`. |
| `lib/services/config-data-item.nix` | `lib/services/config-data-item.nix` | modified | Test-path comment retargeted to `integrations/nixos/tests/etc/test.nix`. |
| `lib/services/test.nix` | `lib/services/test.nix` | modified | Takes `lib` as a parameter instead of `import ../.`, so it runs against whichever `lib` the consumer pins. Imports `./.` rather than `./lib.nix`. |
| `lib/services/vendor/meta-maintainers.nix` | `modules/generic/meta-maintainers.nix` | modified | `lib`-only dependency of the portable layer; vendored so `lib/services` needs nothing outside itself. The note on why it declares no `meta.maintainers` of its own points at nixpkgs' `ci/OWNERS`, which is where this file's owners are recorded and which has no counterpart here. |
| `lib/services/vendor/assertions.nix` | `lib/modules/generic/assertions.nix` | verbatim | `lib`-only dependency of the portable layer; vendored so `lib/services` needs nothing outside itself. Upstream keeps this next to `meta-maintainers.nix` under `lib/modules/generic/`, where it is class-agnostic (`_class = null`) rather than a NixOS module; the pinned nixpkgs still has the NixOS-only copy at `nixos/modules/misc/assertions.nix`. |
| `compliance/default.nix` | `pkgs/build-support/testers/modular-service-compliance.nix` | modified | Two doc-link comments retargeted from the nixpkgs manual to `compliance/README.md`. |
| `integrations/nixos/modular/default.nix` | `nixos/modules/system/service/modular/default.nix` | modified | Registers an `easytier` variant, which upstream's registry omits. Service instances are keyed on `modularServices.<name>` rather than on package `passthru`, and the note on `_file` points at `../tests/modular-variants.nix`. |
| `integrations/nixos/modular/<pkg>/<svc>/default.nix` | `nixos/modules/system/service/modular/<pkg>/<svc>/default.nix` | modified | The pure half of each variant. Imports `(modularServices.<name> pkgs)` instead of `pkgs.<pkg>.services.<svc>`, which is the nixpkgs copy; `modularServices` reaches the variant as a root special arg set in `../../../systemd/system.nix`. `python-http-server` imports its base by path in both trees, here `../../../tests/etc/python-http-server.nix`. `easytier` has no upstream counterpart. |
| `integrations/nixos/modular/<pkg>/<svc>/system.nix` | `nixos/modules/system/service/modular/<pkg>/<svc>/system.nix` | verbatim | The systemd half of each variant, holding what the service modules below no longer do. `easytier` has no upstream counterpart: like `python-http-server` it defines nothing, and exists so that every service in `modular-services/` is registered. |
| `integrations/nixos/systemd/system/default.nix` | `nixos/modules/system/service/systemd/system/default.nix` | modified | The portable-layer import becomes `../../../../lib/services`. This is the single line that made the whole in-tree `lib/services` reachable from a NixOS evaluation. `extraRootSpecialArgs` gains `modularServices` alongside `pkgs`, since a variant reaches its base through that set rather than through package `passthru`. |
| `integrations/nixos/systemd/defaults.nix` | `nixos/modules/system/service/systemd/defaults.nix` | verbatim | |
| `integrations/nixos/systemd/service.nix` | `nixos/modules/system/service/systemd/service.nix` | verbatim | |
| `integrations/nixos/systemd/system/config-data-path.nix` | `nixos/modules/system/service/systemd/system/config-data-path.nix` | modified | Test-path comment retargeted to `../../tests/etc/test.nix`. |
| `integrations/nixos/systemd/user/default.nix` | `nixos/modules/system/service/systemd/user/default.nix` | modified | The portable-layer import becomes `../../../../lib/services`, as in `../system/default.nix`. |
| `integrations/nixos/systemd/user/config-data-path.nix` | `nixos/modules/system/service/systemd/user/config-data-path.nix` | verbatim | |
| `integrations/nixos/systemd/user/defaults.nix` | `nixos/modules/system/service/systemd/user/defaults.nix` | verbatim | |
| `integrations/nixos/tests/units.nix` | `nixos/modules/system/service/systemd/system/test.nix` | modified | Run-instruction comment only; `evalSystem` now comes from `integrations/nixos/lib.nix` instead of `all-tests.nix`, which needs no change to the file. |
| `integrations/nixos/tests/modular-variants.nix` | `nixos/modules/system/service/modular/test.nix` | modified | Run-instruction comment, the `system.stateVersion` this repository's tests use, and the expected attribution paths, which name `integrations/nixos/modular/` and `modular-services/` rather than the nixpkgs tree. |
| `integrations/nixos/tests/user-units.nix` | `nixos/modules/system/service/systemd/user/test.nix` | modified | Run-instruction comment only, as for `units.nix`. |
| `integrations/nixos/tests/user-service.nix` | `nixos/tests/modular-user-service.nix` | modified | Run-instruction comment only. |
| `integrations/nixos/tests/compliance.nix` | `nixos/tests/system-services-compliance.nix` | modified | Drops the `callTest` parameter and the trailing `mapAttrs ... callTest` block, which exist only to satisfy `all-tests.nix` plumbing. Calls `self.lib.mkComplianceSuite` instead of `pkgs.testers.modularServiceCompliance`. The `systemdEvalTests` block is unchanged. |
| `integrations/nixos/tests/etc/test.nix` | `nixos/tests/modular-service-etc/test.nix` | modified | Run-instruction comment, and `config` is taken on the `server` node's module arguments rather than the test's, which is where `modularServices` is declared. |
| `integrations/nixos/tests/etc/python-http-server.nix` | `nixos/tests/modular-service-etc/python-http-server.nix` | verbatim | |
| `integrations/nixos/tests/packages/autopush-rs.nix` | `nixos/tests/autopush-rs.nix` | modified | Keeps the `autoconnect.settings.auth_keys` line, which the pinned nixpkgs has and the variant split has not yet reached. |
| `integrations/nixos/tests/packages/easytier.nix` | `nixos/tests/easytier-modular.nix` | modified | `pkgs.easytier.services.default` becomes `config.modularServices.easytier.default`. Upstream registers no `easytier` variant, so this one has no counterpart there. |
| `integrations/nixos/tests/packages/ghostunnel.nix` | `nixos/tests/ghostunnel-modular.nix` | verbatim | |
| `integrations/nixos/tests/packages/git-pages.nix` | `nixos/tests/git-pages.nix` | modified | `pkgs.git-pages.services.default` becomes `config.modularServices.git-pages.default`, the variant path the package tests here import. |
| `integrations/nixos/tests/packages/holo-daemon.nix` | `nixos/tests/holo-daemon-modular.nix` | verbatim | |
| `integrations/nixos/tests/packages/snid.nix` | `nixos/tests/snid.nix` | verbatim | |
| `integrations/nixos/tests/packages/tlshd.nix` | `nixos/tests/tlshd.nix` | verbatim | |
| `integrations/nixos/tests/packages/php-fpm.nix` | `nixos/tests/php/fpm-modular.nix` | modified | Run-instruction comment only. The `php.buildEnv` wrapper it relies on moved to `integrations/nixos/tests/default.nix`, from `nixos/tests/php/default.nix`. |
| `modular-services/autopush-rs/service-autoconnect.nix` | `pkgs/by-name/au/autopush-rs/service-autoconnect.nix` | modified | The systemd hardening moves to `integrations/nixos/modular/autopush-rs/autoconnect/system.nix`, leaving the service itself naming no service manager. |
| `modular-services/autopush-rs/service-autoendpoint.nix` | `pkgs/by-name/au/autopush-rs/service-autoendpoint.nix` | modified | The systemd hardening moves to `integrations/nixos/modular/autopush-rs/autoendpoint/system.nix`, leaving the service itself naming no service manager. |
| `modular-services/easytier/service.nix` | `pkgs/by-name/ea/easytier/service.nix` | verbatim | |
| `modular-services/ghostunnel/service.nix` | `pkgs/by-name/gh/ghostunnel/service.nix` | modified | The systemd definitions, including the credential flags `mainExecStart` appends, move to `integrations/nixos/modular/ghostunnel/default/system.nix`. |
| `modular-services/git-pages/service.nix` | `pkgs/by-name/gi/git-pages/service.nix` | verbatim | |
| `modular-services/holo-daemon/service.nix` | `pkgs/by-name/ho/holo-daemon/service.nix` | verbatim | |
| `modular-services/ktls-utils/service.nix` | `pkgs/by-name/kt/ktls-utils/service.nix` | modified | The systemd definitions move to `integrations/nixos/modular/ktls-utils/default/system.nix`. |
| `modular-services/snid/service.nix` | `pkgs/by-name/sn/snid/service.nix` | modified | The systemd definitions move to `integrations/nixos/modular/snid/default/system.nix`. |
| `modular-services/php/service.nix` | `pkgs/development/interpreters/php/service.nix` | modified | Test-path comment retargeted to `integrations/nixos/tests/packages/php-fpm.nix`. The systemd definitions move to `integrations/nixos/modular/php/default/system.nix`, which takes `coreutils` with them, so the service's non-module dependencies narrow to `{ formats }`. |
| `doc/modular-services.md` | `doc/modules/modular-services.section.md`, `nixos/doc/manual/development/modular-services.md` | modified | One chapter where nixpkgs has two: the portable material lives in the nixpkgs manual and the NixOS manual carries a pointer chapter with the systemd-specific options, whereas this is one book about the subsystem rather than one chapter per integration. Adds a note on this repository's relationship to nixpkgs; the consumption example uses `modularServices`. The two option-type links become absolute NixOS-manual URLs, because the chapter renders as a standalone book where a bare `#anchor` is resolved against the book and rejected when it names nothing. Links into this repository are absolute for the same reason, so that they resolve both here and in the rendered manual. Keeps the `@PORTABLE_SERVICE_OPTIONS@` / `@SYSTEMD_SERVICE_OPTIONS@` placeholders. |
| `doc/writing-and-reviewing.md` | `nixos/README-modular-services.md` | modified | Review checklist and worked examples retargeted at this repository's paths, and links into it made absolute. Every heading gains an explicit anchor, because the file is a chapter of the rendered manual rather than a standalone README. |
| `compliance/README.md` | `doc/build-helpers/testers.chapter.md` | modified | Extracted from the `modularServiceCompliance` section of the testers chapter; the nixpkgs-manual markup is dropped and the invocation example uses `self.lib.mkComplianceSuite`. |

## Not ported

- `nixos/tests/all-tests.nix`'s `callTest` / `findTests` plumbing. It exists to
  satisfy the nixpkgs test registry and has no counterpart here;
  `pkgs.testers.runNixOSTest` returns a derivation directly.
- `nixos/modules/misc/documentation/modular-services.nix`, including its
  `bundledModularServiceNames` list. Replaced by
  [`integrations/nixos/documentation.nix`](./integrations/nixos/documentation.nix),
  which is keyed on `modularServices` rather than on package `passthru`, and
  which covers `easytier` and `holo-daemon` -- two service modules the nixpkgs
  registry is missing. The list it renders is
  [`doc/registry.nix`](./doc/registry.nix), which
  `checks.docs-registry-complete` keeps complete. Upstream instead derives its
  list from the variant registry and drops the `python-http-server` fixture from
  it; here the registry check is what keeps the list complete, and the fixture
  is not a `modularServices` entry to begin with. Rendering the services rather
  than their variants loses no option: a variant under
  [`integrations/nixos/modular/`](./integrations/nixos/modular) declares none,
  it only defines systemd config.
- `nixos/lib/default.nix`. Its new `modularServices` attribute exposes the
  variant registry through nixpkgs' `lib`, which this repository cannot add to.
  The registry is reached as `config.modularServices` instead, and
  [`integrations/nixos/modular/default.nix`](./integrations/nixos/modular/default.nix)
  directly.
- `ci/OWNERS`, and `modules/generic/meta-maintainers/test.nix`. Both are nixpkgs
  CI plumbing; neither the ownership file nor that test is vendored here.
- The nixpkgs manual's build plumbing for the modular-services chapter:
  `doc/doc-support/package.nix`, `doc/redirects.json` and the
  `package-module-options` entry in `pkgs/top-level/all-packages.nix`. This book
  is built by [`doc/default.nix`](./doc/default.nix) instead.
- `nixos/modules/system/service/README.md`. Superseded by
  [`integrations/nixos/README.md`](./integrations/nixos/README.md).
- `pkgs/by-name/gi/git-pages/package.nix`. Its `passthru.services.default`
  is the wiring that lives in
  [`modular-services/default.nix`](./modular-services/default.nix) here. The
  same file also patches the package so the server creates its storage root
  with `os.MkdirAll`, which the service module depends on; the `git-pages`
  entry in `modular-services/default.nix` applies that patch to the pinned
  package until nixpkgs carries it.

[nixpkgs]: https://github.com/NixOS/nixpkgs
[Home Manager]: https://github.com/nix-community/home-manager
[`nix-darwin`]: https://github.com/nix-darwin/nix-darwin
[finix]: https://github.com/finix-community/finix
[NixNG]: https://github.com/nix-community/NixNG
