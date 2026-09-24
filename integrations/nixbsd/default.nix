# The NixBSD integration: the module a NixBSD configuration imports to get
# modular services from this repository, on top of FreeBSD rc.
{
  _class = "nixos";

  imports = [
    ./disable-upstream.nix
    ./freebsd
  ];
}
