{ modularServices, pkgs, ... }:
{
  _class = "service";
  imports = [ (modularServices.php pkgs) ];
}
