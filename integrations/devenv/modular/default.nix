# Registry of the devenv variants of the modular services, keyed by
# `<environment>.<pkg>.<service>`, as in `../../nixos/modular/default.nix`.
#
# Only the services listed here have a devenv variant.
{
  system = {
    postgresql.default = ./postgresql/default/system.nix;
  };
}
