{
  lib,
  config,
  options,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib)
    concatMapAttrs
    mkOption
    types
    concatLists
    mapAttrsToList
    ;

  portable-lib = import ../../../../lib/services { inherit lib; };

  dash =
    before: after:
    if after == "" then
      before
    else if before == "" then
      after
    else
      "${before}-${after}";

  mkConfiguration =
    userName:
    portable-lib.configure {
      serviceManagerPkgs = pkgs;
      extraRootModules = [
        ../service.nix
        (import ./config-data-path.nix userName)
      ];
      extraRootSpecialArgs = {
        systemdPackage = config.systemd.package;
        defaultWantedBy = [ "default.target" ];
      };
    };

  # Like system/default.nix's makeUnits. A sub-service joins its parent's name
  # with a dash, so the whole tree is flat by the time it is a set of units.
  makeUnits =
    unitType: prefix: service:
    concatMapAttrs (unitName: unitModule: {
      # A function, not a bare attrset: the systemd unit types set
      # `shorthandOnlyDefinesConfig`, which makes an attrset a `config` body.
      ${dash prefix unitName} =
        { ... }:
        {
          imports = [ unitModule ];
        };
    }) service.systemd.${unitType}
    // concatMapAttrs (
      subServiceName: subService: makeUnits unitType (dash prefix subServiceName) subService
    ) service.services;

  # The units of one user's whole service tree, keyed by the name that the
  # systemd instance of the user knows them by.
  localUnits =
    unitType: user:
    concatMapAttrs (serviceName: service: makeUnits unitType serviceName service) user.services;

  # `systemd.user.units` writes `/etc/systemd/user`, which every user reads. A
  # unit of one user only can not go there, so evaluate and write it here, with
  # the helpers that NixOS uses for its own units.
  evalUnits =
    unitType: units:
    (lib.evalModules {
      modules = [
        { options.units = mkOption { type = utils.systemdUtils.types.${unitType}; }; }
        { inherit units; }
      ];
    }).config.units;

  toUnit = {
    services = utils.systemdUtils.lib.serviceToUnit;
    sockets = utils.systemdUtils.lib.socketToUnit;
  };

  # Unit file name -> { source, wantedBy } for the per-user profile. The systemd
  # instance of the user finds these through `$XDG_DATA_DIRS`.
  profileUnits =
    user:
    concatMapAttrs (
      unitType: defToUnit:
      concatMapAttrs (
        _: def:
        let
          unit = defToUnit def;
        in
        {
          ${def.name} = {
            source = "${utils.systemdUtils.lib.makeUnit def.name unit}/${def.name}";
            inherit (unit) wantedBy;
          };
        }
      ) (evalUnits unitType (localUnits unitType user))
    ) toUnit;

  makeEtcLinks =
    prefix: service:
    lib.mapAttrsToList (
      _: cfg:
      let
        # cfg.path is e.g. /etc/profiles/per-user/alice/etc/xdg/user-services/foo/item
        # Strip the leading /etc/profiles/per-user/<user>/ to get the within-profile path.
        stripped = lib.removePrefix "/etc/profiles/per-user/" cfg.path;
        perUserPath = lib.concatStringsSep "/" (lib.tail (lib.splitString "/" stripped));
      in
      lib.optionalAttrs cfg.enable { "${perUserPath}" = cfg.source; }
    ) (service.configData or { })
    ++ concatLists (
      mapAttrsToList (
        subServiceName: subService: makeEtcLinks (dash prefix subServiceName) subService
      ) service.services
    );

  # Build the per-user profile package containing the unit files and configData.
  # `user` is the user submodule config.
  makeUserPkg =
    userName: user:
    let
      etcLinks = lib.foldl' (acc: m: acc // m) { } (
        concatLists (mapAttrsToList (serviceName: service: makeEtcLinks serviceName service) user.services)
      );

      unitSymlinks = concatMapAttrs (
        unitFile: unit:
        {
          "share/systemd/user/${unitFile}" = unit.source;
        }
        // lib.listToAttrs (
          map (
            target: lib.nameValuePair "share/systemd/user/${target}.wants/${unitFile}" "../${unitFile}"
          ) unit.wantedBy
        )
      ) (profileUnits user);
    in
    pkgs.runCommand "user-services-${userName}" { preferLocalBuild = true; } ''
      ${lib.concatStringsSep "\n" (
        mapAttrsToList (dest: src: ''
          mkdir -p "$out/$(dirname "${dest}")"
          ln -s ${lib.escapeShellArg src} "$out/${dest}"
        '') (unitSymlinks // etcLinks)
      )}
    '';
in
{
  _class = "nixos";

  # First half of the magic: mix systemd logic into the otherwise abstract services
  options = {
    users.users = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            options.services = mkOption {
              description = ''
                A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services)
                that are configured as per-user systemd user units.
              '';
              type = types.attrsOf (mkConfiguration name).serviceSubmodule;
              default = { };
              visible = "shallow";
            };

            config.packages = lib.mkIf (config.services != { }) [
              (makeUserPkg name config)
            ];
          }
        )
      );
    };
  };

  # Second half of the magic: siphon units that were defined in isolation to the system
  config = {

    assertions = concatLists (
      mapAttrsToList (
        userName: user:
        concatLists (
          mapAttrsToList (
            serviceName: cfg:
            portable-lib.getAssertions (
              options.users.users.loc
              ++ [
                userName
                "services"
                serviceName
              ]
            ) cfg
          ) user.services
        )
      ) config.users.users
    );

    warnings = concatLists (
      mapAttrsToList (
        userName: user:
        concatLists (
          mapAttrsToList (
            serviceName: cfg:
            portable-lib.getWarnings (
              options.users.users.loc
              ++ [
                userName
                "services"
                serviceName
              ]
            ) cfg
          ) user.services
        )
      ) config.users.users
    );
  };
}
