# The NixOS integration: the module a NixOS configuration imports to get
# modular services from this repository instead of from nixpkgs.
{
  _class = "nixos";

  imports = [
    ./disable-upstream.nix
    ./systemd
  ];
}
