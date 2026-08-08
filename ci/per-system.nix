# The outputs `default.nix` produces for the one system it was called with.
#
# `flake.nix` publishes these keyed by system and everything else as-is, so
# this list is what decides which is which. `non-flake.nix` reads the same list
# and proves the split is honest: every output *not* named here evaluates with
# no system and no package set at all.
[
  "checks"
  "packages"
  "devShells"
  "formatter"
  "ci"
]
