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
turn [`environments/nixos/disable-upstream.nix`](./environments/nixos/disable-upstream.nix)
into a no-op without any error.

## No per-file provenance headers

Vendored files carry **no** added header comment. That is deliberate: keeping
them byte-identical to upstream makes a plain `diff` against a nixpkgs checkout
a usable answer to "what did we change", and a header would defeat it on every
single file. The files that genuinely had to change are marked `modified` below
with the reason; those are the only places where a divergence exists at all.

No per-row revision either. [`flake.lock`](./flake.lock) records the pin, and a
second copy per row would only be another thing to keep in step, touching all 34
rows on every re-vendor. Note that the pin is the `nixos-unstable` channel, which
advances only once Hydra has built it and so trails the nixpkgs default branch by
a few days: a file vendored from the branch can be *newer* than its counterpart
in the pinned nixpkgs.

## The table

| repo path | nixpkgs path | state | reason |
|---|---|---|---|
| `lib/services/default.nix` | `lib/services/lib.nix` | modified | Renamed to `default.nix` so `import ./lib/services` resolves. The `configure` docstring is retargeted from a `nix-darwin` sketch to the `environments/<name>/` contract, which makes it the how-to-add-an-environment guide. |
| `lib/services/service.nix` | `lib/services/service.nix` | modified | The two out-of-tree imports point at `./vendor/` instead of `../../modules/generic/` and `../../nixos/modules/misc/`. |
| `lib/services/config-data.nix` | `lib/services/config-data.nix` | modified | Test-path comment retargeted to `environments/nixos/tests/etc/test.nix`. |
| `lib/services/config-data-item.nix` | `lib/services/config-data-item.nix` | modified | Test-path comment retargeted to `environments/nixos/tests/etc/test.nix`. |
| `lib/services/test.nix` | `lib/services/test.nix` | modified | Takes `lib` as a parameter instead of `import ../.`, so it runs against whichever `lib` the consumer pins. Imports `./.` rather than `./lib.nix`. |
| `lib/services/vendor/meta-maintainers.nix` | `modules/generic/meta-maintainers.nix` | verbatim | `lib`-only dependency of the portable layer; vendored so `lib/services` needs nothing outside itself. |
| `lib/services/vendor/assertions.nix` | `nixos/modules/misc/assertions.nix` | verbatim | `lib`-only dependency of the portable layer; vendored so `lib/services` needs nothing outside itself. |
| `compliance/default.nix` | `pkgs/build-support/testers/modular-service-compliance.nix` | modified | Two doc-link comments retargeted from the nixpkgs manual to `compliance/README.md`. |
| `environments/nixos/systemd/system.nix` | `nixos/modules/system/service/systemd/system.nix` | modified | The portable-layer import becomes `../../../lib/services`. This is the single line that made the whole in-tree `lib/services` reachable from a NixOS evaluation. |
| `environments/nixos/systemd/service.nix` | `nixos/modules/system/service/systemd/service.nix` | verbatim | |
| `environments/nixos/systemd/config-data-path.nix` | `nixos/modules/system/service/systemd/config-data-path.nix` | modified | Test-path comment retargeted to `../tests/etc/test.nix`. |
| `environments/nixos/systemd/user.nix` | `nixos/modules/system/service/systemd/user.nix` | verbatim | Still a stub upstream. |
| `environments/nixos/tests/units.nix` | `nixos/modules/system/service/systemd/test.nix` | modified | Run-instruction comment only; `evalSystem` now comes from `environments/nixos/lib.nix` instead of `all-tests.nix`, which needs no change to the file. |
| `environments/nixos/tests/compliance.nix` | `nixos/tests/system-services-compliance.nix` | modified | Drops the `callTest` parameter and the trailing `mapAttrs ... callTest` block, which exist only to satisfy `all-tests.nix` plumbing. Calls `self.lib.mkComplianceSuite` instead of `pkgs.testers.modularServiceCompliance`. The `systemdEvalTests` block is unchanged. |
| `environments/nixos/tests/etc/test.nix` | `nixos/tests/modular-service-etc/test.nix` | modified | Run-instruction comment only. |
| `environments/nixos/tests/etc/python-http-server.nix` | `nixos/tests/modular-service-etc/python-http-server.nix` | verbatim | |
| `environments/nixos/tests/packages/autopush-rs.nix` | `nixos/tests/autopush-rs.nix` | modified | Takes `serviceModules` as a non-module dependency; `pkgs.autopush-rs.services.<n>` becomes `(serviceModules.autopush-rs-<n> pkgs)`. |
| `environments/nixos/tests/packages/easytier.nix` | `nixos/tests/easytier-modular.nix` | modified | Takes `serviceModules` as a non-module dependency; `pkgs.easytier.services.default` becomes `(serviceModules.easytier pkgs)`. |
| `environments/nixos/tests/packages/ghostunnel.nix` | `nixos/tests/ghostunnel-modular.nix` | modified | Takes `serviceModules` as a non-module dependency; `pkgs.ghostunnel.services.default` becomes `(serviceModules.ghostunnel pkgs)`. |
| `environments/nixos/tests/packages/holo-daemon.nix` | `nixos/tests/holo-daemon-modular.nix` | modified | Takes `serviceModules` as a non-module dependency; `pkgs.holo-daemon.services.default` becomes `(serviceModules.holo-daemon pkgs)`. |
| `environments/nixos/tests/packages/snid.nix` | `nixos/tests/snid.nix` | modified | Takes `serviceModules` as a non-module dependency; `pkgs.snid.services.default` becomes `(serviceModules.snid pkgs)`. |
| `environments/nixos/tests/packages/tlshd.nix` | `nixos/tests/tlshd.nix` | modified | Takes `serviceModules` as a non-module dependency; `pkgs.ktls-utils.services.default` becomes `(serviceModules.ktls-utils pkgs)`. |
| `environments/nixos/tests/packages/php-fpm.nix` | `nixos/tests/php/fpm-modular.nix` | modified | Takes `serviceModules` as a non-module dependency; `php.services.default` becomes `(serviceModules.php pkgs)`. The `php.buildEnv` wrapper it relies on moved to `environments/nixos/tests/default.nix`, from `nixos/tests/php/default.nix`. |
| `service-modules/autopush-rs/service-autoconnect.nix` | `pkgs/by-name/au/autopush-rs/service-autoconnect.nix` | verbatim | |
| `service-modules/autopush-rs/service-autoendpoint.nix` | `pkgs/by-name/au/autopush-rs/service-autoendpoint.nix` | verbatim | |
| `service-modules/easytier/service.nix` | `pkgs/by-name/ea/easytier/service.nix` | verbatim | |
| `service-modules/ghostunnel/service.nix` | `pkgs/by-name/gh/ghostunnel/service.nix` | verbatim | |
| `service-modules/holo-daemon/service.nix` | `pkgs/by-name/ho/holo-daemon/service.nix` | verbatim | |
| `service-modules/ktls-utils/service.nix` | `pkgs/by-name/kt/ktls-utils/service.nix` | verbatim | |
| `service-modules/snid/service.nix` | `pkgs/by-name/sn/snid/service.nix` | verbatim | |
| `service-modules/php/service.nix` | `pkgs/development/interpreters/php/service.nix` | modified | Test-path comment retargeted to `environments/nixos/tests/packages/php-fpm.nix`. |
| `doc/modular-services.md` | `nixos/doc/manual/development/modular-services.md` | modified | Adds a note on this repository's relationship to nixpkgs; the consumption example uses `serviceModules`; the contributor-doc link points at `doc/writing-and-reviewing.md`. The two option-type links become absolute NixOS-manual URLs, because the chapter renders as a standalone book where a bare `#anchor` resolves to nothing. Keeps the `@PORTABLE_SERVICE_OPTIONS@` / `@SYSTEMD_SERVICE_OPTIONS@` placeholders. |
| `doc/writing-and-reviewing.md` | `nixos/README-modular-services.md` | modified | Review checklist and worked examples retargeted at this repository's paths. |
| `compliance/README.md` | `doc/build-helpers/testers.chapter.md` | modified | Extracted from the `modularServiceCompliance` section of the testers chapter; the nixpkgs-manual markup is dropped and the invocation example uses `self.lib.mkComplianceSuite`. |

## Not ported

- `nixos/tests/all-tests.nix`'s `callTest` / `findTests` plumbing. It exists to
  satisfy the nixpkgs test registry and has no counterpart here;
  `pkgs.testers.runNixOSTest` returns a derivation directly.
- `nixos/modules/misc/documentation/modular-services.nix`. Replaced by
  [`doc/service-modules.nix`](./doc/service-modules.nix), which is keyed on
  `serviceModules` rather than on package `passthru`, and which covers
  `easytier` and `holo-daemon` — two service modules the nixpkgs registry is
  missing. `checks.docs-registry-complete` keeps it complete.
- `nixos/modules/system/service/README.md`. Superseded by
  [`environments/nixos/README.md`](./environments/nixos/README.md).

[nixpkgs]: https://github.com/NixOS/nixpkgs
