# The vendored per-package service modules, as `serviceModules.<name> pkgs`.
#
# These modules are environment-agnostic by construction: every one of them
# declares `_class = "service"` and none imports anything from `lib/services`.
# They therefore live outside `environments/`.
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
# `serviceModules.<pkg>` is the canonical way to consume a service from this
# repo. `overlays.packageServices` exists as an opt-in compatibility shim for
# code written against `pkgs.<pkg>.services.*`; see ../overlays/README section
# in ../README.md for why it is not the default.
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
        inherit (pkgs) formats coreutils;
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
