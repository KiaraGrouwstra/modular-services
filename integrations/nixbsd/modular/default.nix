# Registry of the NixBSD variants of the modular services, keyed by
# `<environment>.<pkg>.<service>`, as in `../../nixos/modular/default.nix`.
#
# Only the services listed here have a NixBSD variant.
{
  system = {
    postgresql.default = ./postgresql/default/system.nix;
  };
}
