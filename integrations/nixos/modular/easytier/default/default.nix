{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.easytier pkgs) ];
}
