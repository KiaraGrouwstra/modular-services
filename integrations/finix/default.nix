# The finix integration: the module a finix configuration imports to get
# modular services from this repository, on top of finit.
{
  _class = "nixos";

  imports = [
    ./disable-upstream.nix
    ./finit
  ];
}
