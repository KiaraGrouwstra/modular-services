# Registry of the NixNG variants of the modular services, keyed by
# `<environment>.<pkg>.<service>`, as in `../../nixos/modular/default.nix`.
#
# Only the services listed here have a NixNG variant.
{
  system = {
    postgresql.default = ./postgresql/default/system.nix;
  };
}
