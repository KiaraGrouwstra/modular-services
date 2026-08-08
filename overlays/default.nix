# Non-invasive overlay: adds `pkgs.modularServices.<name>`, leaving every
# package derivation untouched. Causes no rebuilds, because it does not
# override anything.
#
# `modularServices.<name> pkgs` is the same value; this overlay only saves
# threading the flake through to the place that needs a service module.
{ modularServices }:

final: _prev: {
  modularServices = builtins.mapAttrs (_name: mkModule: mkModule final) modularServices;
}
