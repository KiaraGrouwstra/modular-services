{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.redlib pkgs) ];
}
