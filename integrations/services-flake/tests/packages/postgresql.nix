# The services-flake variant of `postgresql`: the server starts, the setup
# script runs, and the server reads its configuration file from the Nix store.
# It runs next to services-flake's own `services.postgres`.
{ config, pkgs, ... }:
{
  services.postgres.upstream = {
    enable = true;
    port = 5434;
  };

  system.services.postgresql = {
    imports = [ config.modularServices.postgresql.default ];
    postgresql = {
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

  settings.processes.test = {
    command = pkgs.writeShellApplication {
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

        echo "services-flake's own postgres runs next to it"
        pg_isready -h 127.0.0.1 -p 5434
      '';
    };
    depends_on = {
      postgresql-setup.condition = "process_completed_successfully";
      upstream.condition = "process_healthy";
    };
  };
}
