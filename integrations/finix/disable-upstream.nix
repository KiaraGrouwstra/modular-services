# finix has no in-tree copy of modular services, so there is nothing to
# disable.
#
# The external `finix-modular-services` module
# (https://github.com/DigitalBrewStudios/finix-modular-services) also declares
# `system.services`. This integration derives from it. Do not import both.
{
  _class = "nixos";

  disabledModules = [ ];
}
