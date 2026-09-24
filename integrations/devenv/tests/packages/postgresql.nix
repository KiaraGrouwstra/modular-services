# The devenv variant of `postgresql`: the server starts, the setup script
# runs, and the server reads its configuration file from the Nix store.
{ config, pkgs, ... }:
{
  system.services.postgresql = {
    imports = [ config.modularServices.postgresql.default ];
    postgresql = {
      # The test runs in the build directory, not in `devenv.root`.
      dataDir = "./data/postgresql";
      settings.unix_socket_directories = ".";
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

  processes.test = {
    exec = "${
      pkgs.writeShellApplication {
        name = "postgresql-test";
        runtimeInputs = [
          config.system.services.postgresql.postgresql.finalPackage
          pkgs.gnugrep
        ];
        text = ''
          export PGHOST=$PWD/data/postgresql PGPORT=5433 PGUSER=postgres
          psql() { command psql -d postgres -v ON_ERROR_STOP=1 -tA "$@"; }

          echo "setup script ran"
          psql -c "SELECT 1 FROM pg_roles WHERE rolname = 'alice'" | grep -q 1
          psql -c "SELECT 1 FROM pg_database WHERE datname = 'alice'" | grep -q 1
          psql -c "SELECT count(*) FROM initial"
          test ! -e data/postgresql/.first_startup

          echo "configuration file comes from the Nix store"
          psql -c "SHOW config_file" | grep -q '^/nix/store/.*-postgresql.conf$'
          psql -c "SHOW port" | grep -qx 5433
        '';
      }
    }/bin/postgresql-test";
    restart.on = "never";
    process-compose.depends_on.postgresql-setup.condition = "process_completed_successfully";
  };
}
