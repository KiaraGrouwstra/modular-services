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
header per file would restate `LICENSE` 34 times and still not say which upstream
the file came from -- which is the question this table answers.

No per-row revision either. [`flake.lock`](./flake.lock) records the pin, and a
second copy per row would only be another thing to keep in step, touching all 34
rows on every re-vendor. Note that the pin is the `nixos-unstable` channel, which
advances only once Hydra has built it and so trails the nixpkgs default branch by
a few days: a file vendored from the branch can be *newer* than its counterpart
in the pinned nixpkgs.

## The table

| repo path | nixpkgs path | state | reason |
|---|---|---|---|
| `lib/services/default.nix` | `lib/services/lib.nix` | modified | Renamed to `default.nix` so `import ./lib/services` resolves. The `configure` docstring is retargeted from a `nix-darwin` sketch to the `integrations/<name>/` contract, which makes it the how-to-add-an-integration guide. |
| `lib/services/service.nix` | `lib/services/service.nix` | modified | The two out-of-tree imports point at `./vendor/` instead of `../../modules/generic/` and `../../nixos/modules/misc/`. |
| `lib/services/config-data.nix` | `lib/services/config-data.nix` | modified | Test-path comment retargeted to `integrations/nixos/tests/etc/test.nix`. |
| `lib/services/config-data-item.nix` | `lib/services/config-data-item.nix` | modified | Test-path comment retargeted to `integrations/nixos/tests/etc/test.nix`. |
| `lib/services/test.nix` | `lib/services/test.nix` | modified | Takes `lib` as a parameter instead of `import ../.`, so it runs against whichever `lib` the consumer pins. Imports `./.` rather than `./lib.nix`. |
| `lib/services/vendor/meta-maintainers.nix` | `modules/generic/meta-maintainers.nix` | verbatim | `lib`-only dependency of the portable layer; vendored so `lib/services` needs nothing outside itself. |
| `lib/services/vendor/assertions.nix` | `nixos/modules/misc/assertions.nix` | verbatim | `lib`-only dependency of the portable layer; vendored so `lib/services` needs nothing outside itself. |
| `compliance/default.nix` | `pkgs/build-support/testers/modular-service-compliance.nix` | modified | Two doc-link comments retargeted from the nixpkgs manual to `compliance/README.md`. |
| `integrations/nixos/systemd/system.nix` | `nixos/modules/system/service/systemd/system.nix` | modified | The portable-layer import becomes `../../../lib/services`. This is the single line that made the whole in-tree `lib/services` reachable from a NixOS evaluation. |
| `integrations/nixos/systemd/service.nix` | `nixos/modules/system/service/systemd/service.nix` | verbatim | |
| `integrations/nixos/systemd/config-data-path.nix` | `nixos/modules/system/service/systemd/config-data-path.nix` | modified | Test-path comment retargeted to `../tests/etc/test.nix`. |
| `integrations/nixos/systemd/user.nix` | `nixos/modules/system/service/systemd/user.nix` | verbatim | Still a stub upstream. |
| `integrations/nixos/tests/units.nix` | `nixos/modules/system/service/systemd/test.nix` | modified | Run-instruction comment only; `evalSystem` now comes from `integrations/nixos/lib.nix` instead of `all-tests.nix`, which needs no change to the file. |
| `integrations/nixos/tests/compliance.nix` | `nixos/tests/system-services-compliance.nix` | modified | Drops the `callTest` parameter and the trailing `mapAttrs ... callTest` block, which exist only to satisfy `all-tests.nix` plumbing. Calls `self.lib.mkComplianceSuite` instead of `pkgs.testers.modularServiceCompliance`. The `systemdEvalTests` block is unchanged. |
| `integrations/nixos/tests/etc/test.nix` | `nixos/tests/modular-service-etc/test.nix` | modified | Run-instruction comment only. |
| `integrations/nixos/tests/etc/python-http-server.nix` | `nixos/tests/modular-service-etc/python-http-server.nix` | verbatim | |
| `integrations/nixos/tests/packages/autopush-rs.nix` | `nixos/tests/autopush-rs.nix` | modified | Takes `modularServices` as a non-module dependency; `pkgs.autopush-rs.services.<n>` becomes `(modularServices.autopush-rs-<n> pkgs)`. |
| `integrations/nixos/tests/packages/easytier.nix` | `nixos/tests/easytier-modular.nix` | modified | Takes `modularServices` as a non-module dependency; `pkgs.easytier.services.default` becomes `(modularServices.easytier pkgs)`. |
| `integrations/nixos/tests/packages/ghostunnel.nix` | `nixos/tests/ghostunnel-modular.nix` | modified | Takes `modularServices` as a non-module dependency; `pkgs.ghostunnel.services.default` becomes `(modularServices.ghostunnel pkgs)`. |
| `integrations/nixos/tests/packages/holo-daemon.nix` | `nixos/tests/holo-daemon-modular.nix` | modified | Takes `modularServices` as a non-module dependency; `pkgs.holo-daemon.services.default` becomes `(modularServices.holo-daemon pkgs)`. |
| `integrations/nixos/tests/packages/snid.nix` | `nixos/tests/snid.nix` | modified | Takes `modularServices` as a non-module dependency; `pkgs.snid.services.default` becomes `(modularServices.snid pkgs)`. |
| `integrations/nixos/tests/packages/tlshd.nix` | `nixos/tests/tlshd.nix` | modified | Takes `modularServices` as a non-module dependency; `pkgs.ktls-utils.services.default` becomes `(modularServices.ktls-utils pkgs)`. |
| `integrations/nixos/tests/packages/php-fpm.nix` | `nixos/tests/php/fpm-modular.nix` | modified | Takes `modularServices` as a non-module dependency; `php.services.default` becomes `(modularServices.php pkgs)`. The `php.buildEnv` wrapper it relies on moved to `integrations/nixos/tests/default.nix`, from `nixos/tests/php/default.nix`. |
| `modular-services/autopush-rs/service-autoconnect.nix` | `pkgs/by-name/au/autopush-rs/service-autoconnect.nix` | verbatim | |
| `modular-services/autopush-rs/service-autoendpoint.nix` | `pkgs/by-name/au/autopush-rs/service-autoendpoint.nix` | verbatim | |
| `modular-services/easytier/service.nix` | `pkgs/by-name/ea/easytier/service.nix` | verbatim | |
| `modular-services/ghostunnel/service.nix` | `pkgs/by-name/gh/ghostunnel/service.nix` | verbatim | |
| `modular-services/holo-daemon/service.nix` | `pkgs/by-name/ho/holo-daemon/service.nix` | verbatim | |
| `modular-services/ktls-utils/service.nix` | `pkgs/by-name/kt/ktls-utils/service.nix` | verbatim | |
| `modular-services/snid/service.nix` | `pkgs/by-name/sn/snid/service.nix` | verbatim | |
| `modular-services/php/service.nix` | `pkgs/development/interpreters/php/service.nix` | modified | Test-path comment retargeted to `integrations/nixos/tests/packages/php-fpm.nix`. |
| `doc/modular-services.md` | `nixos/doc/manual/development/modular-services.md` | modified | Adds a note on this repository's relationship to nixpkgs; the consumption example uses `modularServices`; the contributor-doc link points at `doc/writing-and-reviewing.md`. The two option-type links become absolute NixOS-manual URLs, because the chapter renders as a standalone book where a bare `#anchor` resolves to nothing. Keeps the `@PORTABLE_SERVICE_OPTIONS@` / `@SYSTEMD_SERVICE_OPTIONS@` placeholders. |
| `doc/writing-and-reviewing.md` | `nixos/README-modular-services.md` | modified | Review checklist and worked examples retargeted at this repository's paths. |
| `compliance/README.md` | `doc/build-helpers/testers.chapter.md` | modified | Extracted from the `modularServiceCompliance` section of the testers chapter; the nixpkgs-manual markup is dropped and the invocation example uses `self.lib.mkComplianceSuite`. |

## Not ported

- `nixos/tests/all-tests.nix`'s `callTest` / `findTests` plumbing. It exists to
  satisfy the nixpkgs test registry and has no counterpart here;
  `pkgs.testers.runNixOSTest` returns a derivation directly.
- `nixos/modules/misc/documentation/modular-services.nix`. Replaced by
  [`integrations/nixos/documentation.nix`](./integrations/nixos/documentation.nix),
  which is keyed on `modularServices` rather than on package `passthru`, and
  which covers `easytier` and `holo-daemon` -- two service modules the nixpkgs
  registry is missing. The list it renders is
  [`doc/registry.nix`](./doc/registry.nix), which
  `checks.docs-registry-complete` keeps complete.
- `nixos/modules/system/service/README.md`. Superseded by
  [`integrations/nixos/README.md`](./integrations/nixos/README.md).

[nixpkgs]: https://github.com/NixOS/nixpkgs
[Home Manager]: https://github.com/nix-community/home-manager
[`nix-darwin`]: https://github.com/nix-darwin/nix-darwin
[finix]: https://github.com/finix-community/finix
[NixNG]: https://github.com/nix-community/NixNG
