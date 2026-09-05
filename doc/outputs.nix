# What each attribute `default.nix` produces is for.
#
# The manual's "Flake attributes" chapter renders this, and
# `checks.docs-outputs-complete` asserts it names the real output surface
# exactly, so a new output cannot arrive undocumented and a removed one cannot
# linger here.
#
# The names in `generated` are not listed but described, because their members
# are as long as the sets themselves and come from the sets themselves.
{
  # Attribute path -> what it is. A path with no `.` is an output that is not
  # an attribute set.
  fixed = {
    "lib.servicesFor" =
      "The portable layer against a caller-supplied `lib`, and the entry point for a new integration.";
    "lib.services" = "`lib.servicesFor` against the `lib` this repository was called with.";
    "lib.mkComplianceSuite" = "The integration-agnostic compliance suite, for a package set.";

    "nixosModules.default" =
      "This repository's implementation and the `modularServices` variant registry, plus the disable of the nixpkgs copy. The one to import.";
    "nixosModules.systemServices" =
      "Just the systemd implementation and the variant registry, without the disable.";
    "nixosModules.disableUpstream" = "Just the disable, without the implementation.";
    "nixosModules.documentation" =
      "Replacement for the option-documentation registry that the disable removes.";

    "overlays.default" = "Adds `pkgs.modularServices.*`. Overrides nothing, so no rebuilds.";
    "overlays.passthruServices" =
      "Opt-in: repoints `pkgs.<pkg>.services.*` at this repository. Excludes `php`, which regenerates its own `passthru`.";

    "packages.docs" = "This manual.";
    "devShells.default" = "`nixfmt-tree` and `jq`.";
    "formatter" = "`nixfmt-tree`, so `nix fmt` formats the tree.";
    "ci.matrix" = "The GitHub Actions job matrix. Consumed only by the workflow.";
  };

  # Top-level attributes the chapter lists from the real set rather than naming
  # them here.
  generated = {
    modularServices = ''
      `modularServices.<pkg> pkgs` yields the service itself, naming no
      service manager. A NixOS configuration imports
      `config.modularServices.<pkg>.<svc>` instead, which is this plus the
      systemd definitions the integration adds. `pkgs.<pkg>.services.*` still
      resolves to the nixpkgs copy unless `overlays.passthruServices` is
      applied.
    '';
    checks = ''
      Every test, integration and repo-level alike. `kind` splits the CI
      matrix: an `eval` check builds on any runner, a `vm` check needs
      `/dev/kvm`. `integration` is the directory under `integrations/` the
      check came from, or `repo` for the checks that belong to no single one.
    '';
  };
}
