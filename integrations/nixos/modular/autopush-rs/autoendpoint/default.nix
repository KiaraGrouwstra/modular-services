{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.autopush-rs-autoendpoint pkgs) ];
}
