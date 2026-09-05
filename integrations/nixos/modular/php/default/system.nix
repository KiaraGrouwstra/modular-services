{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.php-fpm;
in
{
  _class = "service";
  imports = [ ./default.nix ];
  meta.maintainers = with lib.maintainers; [ aanderse ];
  config = {
    # `php-fpm` reloads on `SIGUSR2`. With a non-zero `systemd_interval` it
    # reports its readiness over the notify socket, so systemd can send the
    # signal itself and wait for the reload to complete. Without one there is
    # nothing to wait for, and the reload falls back to `ExecReload`.
    systemd.mainExecReload = lib.mkIf (
      cfg.settings.systemd_interval == 0
    ) "${pkgs.coreutils}/bin/kill -USR2 $MAINPID";

    systemd.service = {
      after = [ "network.target" ];
      documentation = [ "man:php-fpm(8)" ];

      serviceConfig = {
        RuntimeDirectory = "php-fpm";
        RuntimeDirectoryPreserve = true;
        Restart = "always";
      }
      // (
        if cfg.settings.systemd_interval != 0 then
          {
            Type = "notify-reload";
            ReloadSignal = "USR2";
          }
        else
          {
            Type = "notify";
          }
      );
    };
  };
}
