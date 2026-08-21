{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.ghostunnel pkgs) ];
}
