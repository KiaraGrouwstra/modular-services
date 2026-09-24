{ pkgs, ... }:
{
  name = "postgresql-modular-service";

  nodes.machine =
    { config, pkgs, ... }:
    {
      system.services.postgresql = {
        imports = [ config.modularServices.postgresql.default ];
        postgresql = {
          identMap = ''
            postgres root postgres
          '';
          initialScript = pkgs.writeText "init.sql" ''
            CREATE TABLE initial (x int);
          '';
          ensureDatabases = [ "alice" ];
          ensureUsers = [
            {
              name = "alice";
              ensureDBOwnership = true;
              ensureClauses.createdb = true;
            }
          ];
          settings.port = 5433;
        };
      };
      environment.systemPackages = [ config.system.services.postgresql.postgresql.finalPackage ];
    };

  testScript = ''
    def psql(query, db="postgres"):
        return machine.succeed(f"psql -h /run/postgresql -p 5433 -U postgres -d {db} -tAc {query!r}").strip()

    machine.wait_for_unit("postgresql-setup.service")

    with subtest("initialScript ran"):
        assert psql("SELECT count(*) FROM initial") == "0"

    with subtest("ensureDatabases and ensureUsers applied"):
        assert psql("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'alice'") == "alice"
        assert psql("SELECT rolcreatedb FROM pg_roles WHERE rolname = 'alice'") == "t"

    with subtest("configuration comes from configData"):
        assert psql("SHOW config_file") == "/etc/system-services/postgresql/postgresql.conf"
        assert psql("SHOW port") == "5433"

    with subtest("reload and restart"):
        machine.succeed("systemctl reload postgresql.service")
        machine.succeed("systemctl restart postgresql.service")
        machine.wait_for_unit("postgresql-setup.service")
        assert psql("SELECT count(*) FROM initial") == "0"
  '';
}
