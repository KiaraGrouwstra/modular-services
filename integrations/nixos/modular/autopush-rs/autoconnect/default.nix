{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.autopush-rs-autoconnect pkgs) ];
}
