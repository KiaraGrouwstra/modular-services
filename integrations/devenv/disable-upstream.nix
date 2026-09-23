# devenv has no copy of modular services, so there is nothing to disable.
#
# Its own services, such as `services.postgres`, use other option names and
# make no processes until `enable = true`. They can thus stay imported.
{
  disabledModules = [ ];
}
