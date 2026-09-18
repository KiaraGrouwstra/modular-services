# The shared compliance suite, run against per-user services.
#
# `compliance.nix` runs the same suite against `system.services`. This one
# proves that the per-user integration honours the same portable contract: the
# services reach a user's own systemd instance, under their short names, and
# reload there.
#
# Run with:
#   nix build .#checks.<system>.nixos-user-compliance-<name>

{
  pkgs,
  self,
  evalSystem,
  runTest,
}:

let
  sharedDir = "/tmp/modular-service-compliance";

  inherit (pkgs) lib;

  userName = "alice";

  # The per-user integration takes its services from `users.users.<name>`,
  # where the system one takes them from `system.services`.
  userModule = services: {
    users.users.${userName} = {
      isNormalUser = true;
      inherit services;
    };
  };

  evalUserServices =
    services:
    evalSystem (
      { ... }:
      {
        imports = [ (userModule services) ];
        system.stateVersion = "25.05";
        fileSystems."/" = {
          device = "/test/dummy";
          fsType = "auto";
        };
        boot.loader.grub.enable = false;
      }
    );
in
self.lib.mkComplianceSuite pkgs {
  inherit sharedDir;
  namePrefix = "user-services-compliance";

  evalConfig =
    { services }:
    let
      machine = evalUserServices services;
    in
    {
      config = machine.config.users.users.${userName}.services;
      checkDrv = machine.config.system.build.toplevel;
    };

  # The global unit is `alice--reload-inner`, but the user's own instance finds
  # it through their profile under the short name.
  callReload =
    path: "systemctl --user --machine=${userName}@ reload ${lib.concatStringsSep "-" path}.service";

  mkTest =
    {
      name,
      services,
      testExe,
    }:
    runTest {
      _class = "nixosTest";
      inherit name;
      nodes.machine = userModule services;
      testScript = ''
        machine.wait_for_unit("multi-user.target")

        # A user instance starts at login. Linger starts one without a login.
        machine.succeed("loginctl enable-linger ${userName}")
        machine.wait_until_succeeds(
          "systemctl --user --machine=${userName}@ is-active basic.target", timeout=60
        )

        machine.succeed("${testExe}")
      '';
      meta.maintainers = with pkgs.lib.maintainers; [ roberth ];
    };
}
