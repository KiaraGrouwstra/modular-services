{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.git-pages pkgs) ];
}
