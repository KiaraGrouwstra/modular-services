# The services-flake integration: the module a process-compose-flake
# configuration imports to get modular services from this repository. It can
# sit next to `services-flake.processComposeModules.default`.
{
  imports = [
    ./disable-upstream.nix
    ./process-compose
  ];
}
