# The modular services themselves, as `modularServices.<name> pkgs`.
#
# A modular service is a module with `_class = "service"`. That is what makes
# this directory the one holding them: `integrations/nixos/systemd/system.nix`
# declares the option surface a service lands in and translates what does, but
# is not itself a service.
#
# They are integration-agnostic by construction: none imports anything from
# `lib/services`. They therefore live outside `integrations/`.
#
# Each entry reproduces two things that nixpkgs puts in the package's
# `passthru.services.<n>`: the `importApply` of the service module with its
# non-module dependencies, and the `<ns>.package` default. Only `service.nix`
# is vendored, so the default has to be restated here.
#
# The default is `lib.mkDefault pkgs.<pkg>` throughout. Upstream mostly uses a
# bare `finalAttrs.finalPackage`, which is an unpriorised definition; `mkDefault`
# is strictly more permissive, and the review checklist only requires that the
# default come from the providing package.
#
# These are the services themselves, and nothing more: an integration adds what
# its service manager needs on top. On NixOS that is
# `integrations/nixos/modular/<pkg>/<svc>/`, reached as
# `config.modularServices.<pkg>.<svc>`, which is how a NixOS configuration
# consumes a service. `overlays.passthruServices` exists as an opt-in
# compatibility shim for code written against `pkgs.<pkg>.services.*`; see
# ../overlays/README section in ../README.md for why it is not the default.
{ lib }:

let
  inherit (lib.modules) importApply;
in
{
  easytier = pkgs: {
    imports = [
      (importApply ./easytier/service.nix {
        inherit (pkgs) formats bash iproute2;
      })
    ];
    easytier.package = lib.mkDefault pkgs.easytier;
  };

  ghostunnel = pkgs: {
    imports = [ (importApply ./ghostunnel/service.nix { }) ];
    ghostunnel.package = lib.mkDefault pkgs.ghostunnel;
  };

  git-pages = pkgs: {
    imports = [
      (importApply ./git-pages/service.nix {
        inherit (pkgs) formats coreutils;
      })
    ];
    # Upstream patches the package so the server creates its storage root with
    # `os.MkdirAll`. The service relies on that instead of an `ExecStartPre`.
    # Drop the override when the pinned nixpkgs carries the patch.
    git-pages.package = lib.mkDefault (
      pkgs.git-pages.overrideAttrs (previousAttrs: {
        patches = (previousAttrs.patches or [ ]) ++ [
          (pkgs.fetchpatch {
            name = "mkdirall-parent-dir-create.patch";
            url = "https://codeberg.org/git-pages/git-pages/commit/507e57edbcfc0ec933a877bf26b1756ca0a61870.patch";
            hash = "sha256-1CjU4yGmDOmYsxo3U44Cg2xLJkrmUOX5ZXTycdLs6OE=";
          })
        ];
      })
    );
  };

  holo-daemon = pkgs: {
    imports = [ (importApply ./holo-daemon/service.nix { inherit pkgs; }) ];
    holo-daemon.package = lib.mkDefault pkgs.holo-daemon;
  };

  ktls-utils = pkgs: {
    imports = [ (importApply ./ktls-utils/service.nix { }) ];
    tlshd.package = lib.mkDefault pkgs.ktls-utils;
  };

  snid = pkgs: {
    imports = [ (importApply ./snid/service.nix { }) ];
    snid.package = lib.mkDefault pkgs.snid;
  };

  php = pkgs: {
    imports = [
      (importApply ./php/service.nix {
        inherit (pkgs) formats;
      })
    ];
    php-fpm.package = lib.mkDefault pkgs.php;
  };

  autopush-rs-autoconnect = pkgs: {
    imports = [ (importApply ./autopush-rs/service-autoconnect.nix { inherit pkgs; }) ];
    autoconnect.package = lib.mkDefault pkgs.autopush-rs;
  };

  autopush-rs-autoendpoint = pkgs: {
    imports = [ (importApply ./autopush-rs/service-autoendpoint.nix { inherit pkgs; }) ];
    autoendpoint.package = lib.mkDefault pkgs.autopush-rs;
  };
}
