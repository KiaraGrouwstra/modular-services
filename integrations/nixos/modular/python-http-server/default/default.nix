{ ... }:
{
  # python-http-server is a test-only service with no `modularServices` entry,
  # so the pure base is imported by path rather than through `modularServices`.
  _class = "service";
  imports = [ ../../../tests/etc/python-http-server.nix ];
}
