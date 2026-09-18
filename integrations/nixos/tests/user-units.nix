# Run:
#   nix build .#checks.<system>.nixos-user-units

{
  evalSystem,
  runCommand,
  hello,
  ...
}:

let
  machine = evalSystem (
    { lib, ... }:
    let
      hello' = lib.getExe hello;
    in
    {
      users.users.alice = {
        isNormalUser = true;
        services.hello.process.argv = [
          hello'
          "--greeting"
          "hi alice"
        ];
        services.bar = {
          process.argv = [
            hello'
            "--greeting"
            "bar"
          ];
          services.db.process.argv = [
            hello'
            "--greeting"
            "bar-db"
          ];
        };
      };

      users.users.bob = {
        isNormalUser = true;
        # Same service name as alice -- must not collide.
        services.hello.process.argv = [
          hello'
          "--greeting"
          "hi bob"
        ];
      };

      system.stateVersion = "26.05";
      fileSystems."/" = {
        device = "/test/dummy";
        fsType = "auto";
      };
      boot.loader.grub.enable = false;
    }
  );

  inherit (machine.config.system.build) toplevel;

  # The per-user profile is built as environment.etc."profiles/per-user/<name>".source.
  # It is a buildEnv derivation whose paths include the user-services package.
  aliceProfile = machine.config.environment.etc."profiles/per-user/alice".source;
  bobProfile = machine.config.environment.etc."profiles/per-user/bob".source;

  # Extract the user-services-* package from the buildEnv paths for symlink-target checks.
  aliceServicePkg = builtins.head (
    builtins.filter (
      p: builtins.match ".*user-services-alice.*" (toString p) != null
    ) aliceProfile.paths
  );

  bobServicePkg = builtins.head (
    builtins.filter (p: builtins.match ".*user-services-bob.*" (toString p) != null) bobProfile.paths
  );
in
runCommand "test-modular-user-service-systemd-units"
  {
    passthru = {
      inherit
        machine
        toplevel
        aliceProfile
        bobProfile
        aliceServicePkg
        bobServicePkg
        ;
    };
  }
  ''
    (
      set -x

      # No unit of a user goes to /etc/systemd/user, which all users read.
      [[ ! -e ${toplevel}/etc/systemd/user/alice--hello.service ]]
      [[ -z "$(find ${toplevel}/etc/systemd/user/ \( -name 'alice*' -o -name 'bob*' \) -print -quit)" ]]

      # Per-user profile for alice: the unit files, under their local names.
      [[ -L ${aliceProfile}/share/systemd/user/hello.service ]]
      [[ -L ${aliceProfile}/share/systemd/user/bar.service ]]
      [[ -L ${aliceProfile}/share/systemd/user/bar-db.service ]]

      # Auto-start symlinks in default.target.wants/.
      [[ -L ${aliceProfile}/share/systemd/user/default.target.wants/hello.service ]]
      [[ -L ${aliceProfile}/share/systemd/user/default.target.wants/bar.service ]]
      [[ -L ${aliceProfile}/share/systemd/user/default.target.wants/bar-db.service ]]

      # The profile holds the unit itself, not a link to a global unit.
      [[ $(readlink ${aliceServicePkg}/share/systemd/user/hello.service) != *alice--* ]]

      # Bob has a service of the same name. It must be his own, not alice's.
      [[ -L ${bobProfile}/share/systemd/user/hello.service ]]
      [[ $(readlink ${bobServicePkg}/share/systemd/user/hello.service) != *alice--* ]]

      # ExecStart in each unit contains the greeting of its own user.
      grep '"hi alice"' ${aliceProfile}/share/systemd/user/hello.service
      grep '"hi bob"' ${bobProfile}/share/systemd/user/hello.service
      grep '"bar-db"' ${aliceProfile}/share/systemd/user/bar-db.service
    )
    touch $out
  ''
