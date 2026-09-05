# Opt-in compatibility shim: point `pkgs.<pkg>.services.*` at this repo's
# service modules instead of the ones vendored in nixpkgs.
#
# Not part of `overlays.default`, and not used by any test in this repo. The
# canonical API is `modularServices.<pkg> pkgs` for the service on its own, and
# `config.modularServices.<pkg>.<svc>` for the NixOS variant of it, for three
# reasons:
#
#   1. `passthru.services` is upstream's attribute. Silently swapping it makes
#      it impossible to A/B a service against the nixpkgs copy, which is much
#      of the point of developing out of tree.
#   2. It cannot be made to work for every package (see `php` below).
#   3. It saves no typing once `modularServices` exists.
#
# `overrideAttrs (finalAttrs: prevAttrs: ...)` is used rather than the
# single-argument form so that `finalAttrs.finalPackage` still resolves to the
# overridden derivation. `passthru` is stripped before building, so replacing
# it causes no rebuild.
{ modularServices }:

final: prev:

let
  inherit (final) lib;

  # Replace the whole `passthru.services` attrset of `prev.${name}`.
  withServices =
    name: mkServices:
    lib.optionalAttrs (prev ? ${name}) {
      ${name} = prev.${name}.overrideAttrs (
        _finalAttrs: prevAttrs: {
          passthru = (prevAttrs.passthru or { }) // {
            services = mkServices;
          };
        }
      );
    };
in

# php is deliberately absent.
#
# `pkgs/development/interpreters/php/generic.nix` gives php its own
# `passthru.overrideAttrs`, and `php.buildEnv` / `php.withExtensions`
# regenerate `passthru.services` from `mkBuildEnv`. An overlay entry here would
# therefore be silently discarded by exactly the wrappers that real
# configurations use. Consume `modularServices.php pkgs`, or on NixOS
# `config.modularServices.php.default`, instead; that is the decisive reason
# `modularServices` is the canonical API rather than an overlay.
lib.foldl' lib.mergeAttrs { } [
  (withServices "easytier" { default = modularServices.easytier final; })
  (withServices "ghostunnel" { default = modularServices.ghostunnel final; })
  (withServices "holo-daemon" { default = modularServices.holo-daemon final; })
  (withServices "ktls-utils" { default = modularServices.ktls-utils final; })
  (withServices "snid" { default = modularServices.snid final; })
  (withServices "autopush-rs" {
    autoconnect = modularServices.autopush-rs-autoconnect final;
    autoendpoint = modularServices.autopush-rs-autoendpoint final;
  })
]
