{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.snid pkgs) ];
}
