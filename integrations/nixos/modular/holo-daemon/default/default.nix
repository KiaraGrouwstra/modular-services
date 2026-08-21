{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.holo-daemon pkgs) ];
}
