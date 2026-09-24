# Remove the in-tree copy of modular services from a NixBSD evaluation, at
# eval time only.
#
# The key is relative to NixBSD's `modulesPath`, thus it matches the NixBSD
# that the consumer evaluates against. `../freebsd/` is derived from this
# module.
#
# NixBSD adds this module only for FreeBSD hosts, after the user modules.
# `disabledModules` also applies to modules that come later.
{
  _class = "nixos";

  disabledModules = [
    # Declares `system.services`.
    "system/service/freebsd/system.nix"
  ];
}
