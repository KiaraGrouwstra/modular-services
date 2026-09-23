# The NixNG integration: the module a NixNG configuration imports to get
# modular services from this repository, on top of NixNG's `init.services`.
# It works with each init system of NixNG (runit and dinit).
{
  imports = [
    ./disable-upstream.nix
    ./init
  ];
}
