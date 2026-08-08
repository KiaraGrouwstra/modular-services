# The manual's "Flake attributes" chapter.
#
# Names come from the outputs themselves, so a service module or a check cannot
# be missing from the manual. Descriptions come from `doc/outputs.nix`, which
# `checks.docs-outputs-complete` holds to the same surface.
#
# Only the shape of the output set is read here, never a value: `checks.docs` is
# this manual, so forcing it would ask the chapter to render itself.
{
  lib,
  self,
  pkgs,
  checks,
}:

let
  inherit (import ./outputs.nix) fixed generated;

  # The outputs `flake.nix` keys by system. Everything else it publishes as-is.
  perSystem = import ../ci/per-system.nix;

  # `doc/outputs.nix` writes descriptions across lines; a table cell is one.
  oneLine = s: lib.concatStringsSep " " (lib.filter (l: l != "") (lib.splitString "\n" s));

  topLevel = path: lib.head (lib.splitString "." path);

  # How each generated group is presented: the attribute a reader writes, and
  # the section that lists what it can be.
  groups = {
    modularServices = {
      member = "<pkg>";
      title = "Service modules";
      anchor = "flake-attributes-service-modules";
    };
    checks = {
      member = "<name>";
      title = "Checks";
      anchor = "flake-attributes-checks";
    };
  };

  rows =
    lib.mapAttrsToList (path: description: {
      inherit path description;
      group = topLevel path;
    }) fixed
    ++ lib.mapAttrsToList (
      name: description:
      let
        g = groups.${name};
      in
      {
        path = "${name}.${g.member}";
        description = "${oneLine description} Listed under [${g.title}](#${g.anchor}).";
        group = name;
      }
    ) generated;

  table =
    rs:
    lib.concatStringsSep "\n" (
      [
        "| attribute | what |"
        "|---|---|"
      ]
      ++ map (r: "| `${r.path}` | ${oneLine r.description} |") (lib.sort (a: b: a.path < b.path) rs)
    );

  portableRows = lib.filter (r: !lib.elem r.group perSystem) rows;
  perSystemRows = lib.filter (r: lib.elem r.group perSystem) rows;

  serviceModules = lib.concatMapStringsSep "\n" (n: "- `modularServices.${n}`") (
    lib.attrNames self.modularServices
  );

  checkRows = lib.concatMapStringsSep "\n" (
    n:
    let
      c = checks.${n};
    in
    "| `${n}` | ${c.kind} | ${c.integration} |"
  ) (lib.attrNames checks);
in

pkgs.writeText "flake-attributes.md" ''
  # Flake attributes {#chap-flake-attributes}

  Everything this repository offers, flake or no flake. `flake.nix` adds no
  output of its own: it pins nixpkgs through `flake.lock` and keys the
  per-system outputs by system, so calling `default.nix` directly gives the same
  surface.

  This chapter is generated from those outputs, and
  `checks.docs-outputs-complete` asserts that every one of them is described
  here.

  ## Whatever the system {#flake-attributes-portable}

  A flake publishes these unkeyed. None of them evaluates a package set, so a
  configuration that imports one pulls in no second nixpkgs.

  ${table portableRows}

  ## For one system {#flake-attributes-per-system}

  These are produced for the system `default.nix` was called with, which is what
  a flake keys as `checks.<system>`, `packages.<system>` and so on.

  ${table perSystemRows}

  ## ${groups.modularServices.title} {#${groups.modularServices.anchor}}

  ${oneLine generated.modularServices}

  ${serviceModules}

  ## ${groups.checks.title} {#${groups.checks.anchor}}

  ${oneLine generated.checks}

  | check | kind | integration |
  |---|---|---|
  ${checkRows}
''
