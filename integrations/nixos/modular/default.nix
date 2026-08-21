# Aggregation registry for modular services, keyed by
# `<environment>.<pkg>.<service>`.
#
# Each service instance (matching `modularServices.<name>`) gets an entry per
# supported environment. Today only the `system` (NixOS system) environment is
# provided; a future `user` environment sits alongside it.
#
# Every modular service is enumerated here - including those with no
# environment-specific configuration - so the directory advertises which
# services are supported on the NixOS system environment.
#
# Entries are paths, not `import <path>`. A bare `import` yields a function,
# which carries no `_file`, so the module system attributes the variant to
# wherever the `deferredModule` was defined instead of to the variant's own
# file. See ../tests/modular-variants.nix.
{
  system = {
    ghostunnel.default = ./ghostunnel/default/system.nix;
    git-pages.default = ./git-pages/default/system.nix;
    snid.default = ./snid/default/system.nix;
    ktls-utils.default = ./ktls-utils/default/system.nix;
    autopush-rs = {
      autoconnect = ./autopush-rs/autoconnect/system.nix;
      autoendpoint = ./autopush-rs/autoendpoint/system.nix;
    };
    php.default = ./php/default/system.nix;
    redlib.default = ./redlib/default/system.nix;
    holo-daemon.default = ./holo-daemon/default/system.nix;
    easytier.default = ./easytier/default/system.nix;
    python-http-server.default = ./python-http-server/default/system.nix;
  };
}
