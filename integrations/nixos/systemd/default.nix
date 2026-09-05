# The modular services implementation for NixOS, on top of systemd.
#
# This does *not* disable the copy vendored in nixpkgs; importing both declares
# `system.services` twice. Import `integrations/nixos` (`nixosModules.default`)
# unless you are disabling upstream some other way.
{
  _class = "nixos";

  imports = [
    ./system
    ./user
  ];
}
