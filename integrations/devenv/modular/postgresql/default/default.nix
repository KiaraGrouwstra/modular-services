{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.postgresql pkgs) ];
}
