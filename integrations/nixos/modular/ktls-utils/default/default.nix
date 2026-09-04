{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.ktls-utils pkgs) ];
}
