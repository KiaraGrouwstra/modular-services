# The devenv integration: the module a devenv configuration imports to get
# modular services from this repository. It can sit next to devenv's own
# services.
{
  imports = [
    ./disable-upstream.nix
    ./processes
  ];
}
