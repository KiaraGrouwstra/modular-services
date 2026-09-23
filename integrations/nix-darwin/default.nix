# The nix-darwin integration: the module a nix-darwin configuration imports to
# get modular services from this repository, on top of launchd. nix-darwin has
# no copy of its own to disable.
{
  _class = "darwin";

  imports = [ ./launchd ];
}
