# The finix variant of `postgresql`: the server starts, the setup script
# runs, and reload and restart work.
{
  name = "postgresql";

  nodes.machine =
    { config, pkgs, ... }:
    {
      services.getty.enable = true;
      services.mdevd.enable = true;

      # See the TODO in `../../modular/postgresql/default/system.nix`.
      users.users.postgres = {
        group = "postgres";
        uid = config.ids.uids.postgres;
      };
      users.groups.postgres.gid = config.ids.gids.postgres;
      finit.tmpfiles.rules = [
        "d /run/postgresql 0755 postgres postgres"
        "d /var/lib/postgresql 0750 postgres postgres"
      ];

      environment.systemPackages = [ pkgs.postgresql ];

      system.services.postgresql = {
        imports = [ config.modularServices.postgresql.default ];
        postgresql = {
          dataDir = "/var/lib/postgresql/data";
          initialScript = pkgs.writeText "init.sql" ''
            CREATE TABLE initial (x int);
          '';
          ensureDatabases = [ "alice" ];
          ensureUsers = [
            {
              name = "alice";
              ensureDBOwnership = true;
            }
          ];
          settings.port = 5433;
        };
      };
    };

  testScript = ''
    import datetime
    import shlex

    timeout = datetime.timedelta(seconds=60)

    def psql(sql):
        return f"echo {shlex.quote(sql)} | su -s /bin/sh postgres -c 'psql -p 5433 -tA'"

    start_all()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("server runs"):
        machine.wait_until_succeeds("initctl status postgresql | grep running", timeout=timeout)

    with subtest("setup script runs"):
        machine.wait_until_succeeds(psql("SELECT 1 FROM pg_roles WHERE rolname = 'alice'") + " | grep -q 1", timeout=timeout)
        machine.succeed(psql("SELECT 1 FROM pg_database WHERE datname = 'alice'") + " | grep -q 1")
        machine.succeed(psql("SELECT count(*) FROM initial"))
        machine.succeed("test ! -e /var/lib/postgresql/data/.first_startup")

    with subtest("configuration file comes from /etc"):
        machine.succeed(psql("SHOW config_file") + " | grep -q /etc/system-services/postgresql/postgresql.conf")

    with subtest("reload"):
        machine.succeed("initctl reload postgresql")
        machine.wait_until_succeeds(psql("SELECT 1"), timeout=timeout)

    with subtest("restart"):
        machine.succeed("initctl restart postgresql")
        machine.wait_until_succeeds(psql("SELECT 1"), timeout=timeout)
        machine.succeed(psql("SELECT count(*) FROM initial"))

    machine.shutdown()
  '';
}
