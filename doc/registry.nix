# Names of the `modularServices` entries whose options get documented, in the
# order they should appear.
#
# This is the shared list, not a rendering of it: an environment that can render
# option documentation reads this and produces whatever its own manual build
# consumes, the way `environments/nixos/documentation.nix` does.
#
# `checks.docs-registry-complete` asserts this matches `modularServices` exactly,
# so it cannot drift the way the nixpkgs original did (which was missing
# `easytier` and `holo-daemon`).
[
  "autopush-rs-autoconnect"
  "autopush-rs-autoendpoint"
  "easytier"
  "ghostunnel"
  "holo-daemon"
  "ktls-utils"
  "php"
  "snid"
]
