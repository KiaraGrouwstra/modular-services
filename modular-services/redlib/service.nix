# Non-module dependencies (`importApply`)
{ }:

# Service module
{
  config,
  lib,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    ;

  cfg = config.redlib;

in
{
  _class = "service";

  options = {
    redlib = {
      package = mkOption {
        description = "Package to use for redlib.";
        defaultText = "The redlib package that provided this module.";
        type = types.package;
      };

      address = mkOption {
        default = "0.0.0.0";
        example = "127.0.0.1";
        type = types.str;
        description = "The address to listen on";
      };

      port = mkOption {
        default = 8080;
        example = 8000;
        type = types.port;
        description = "The port to listen on";
      };

      settings = lib.mkOption {
        type = lib.types.submodule {
          freeformType =
            with types;
            attrsOf (
              nullOr (oneOf [
                bool
                int
                str
              ])
            );
          options = { };
        };
        default = { };
        description = ''
          See [GitHub](https://github.com/redlib-org/redlib/tree/main?tab=readme-ov-file#configuration) for available settings.
        '';
      };
    };
  };

  config = {
    process.argv = [
      (lib.getExe cfg.package)
      "--port"
      (toString cfg.port)
      "--address"
      cfg.address
    ];
  };

  meta = {
    maintainers = with lib.maintainers; [ Guanran928 ];
  };
}
