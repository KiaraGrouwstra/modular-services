# The GitHub Actions matrix, computed from the same set that produces `checks`.
# Consumed only by .github/workflows/ci.yml, via
# `nix eval --json .#ci.<system>.matrix`, which splits `include` on `kind` into
# the eval-checks and vm-tests jobs.
#
# Adding an integration adds its entries here automatically; `integration` is
# carried through purely as a job label.
{ lib, checks }:

{
  include = lib.mapAttrsToList (name: c: {
    inherit name;
    inherit (c) kind integration;
  }) checks;
}
