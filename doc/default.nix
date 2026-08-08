# Renders the modular services manual chapter, with the portable and
# systemd-specific option references substituted in.
#
# This reproduces the `nixosOptionsDoc` plumbing that
# `nixos/doc/manual/default.nix` applies to the same chapter, so that the
# `@PORTABLE_SERVICE_OPTIONS@` / `@SYSTEMD_SERVICE_OPTIONS@` placeholders in
# modular-services.md keep working outside the NixOS manual build.
{
  lib,
  self,
  pkgs,
}:

let
  inherit (pkgs) buildPackages runCommand;
  inherit (lib) evalModules modules;

  # Where nixosOptionsDoc puts options.json (nixos/doc/manual/common.nix).
  outputPath = "share/doc/nixos";

  inherit (self) revision;

  # Declaration sites must not point into the store, or the build gains a
  # reference to the source tree.
  stripPrefix = lib.removePrefix "${self}/";

  transformOptions =
    opt:
    opt
    // {
      declarations = map (d: stripPrefix (toString d)) opt.declarations;
    };

  portableServiceOptions = buildPackages.nixosOptionsDoc {
    inherit
      (evalModules {
        modules = [
          (modules.importApply ../lib/services/service.nix {
            pkgs = throw "modular-services docs / portableServiceOptions: Do not reference pkgs in docs";
          })
        ];
      })
      options
      ;
    inherit revision transformOptions;
    warningsAreErrors = true;
  };

  # Mirrors upstream in evaluating systemd/service.nix without its
  # `systemdPackage` specialArg: the resulting missing-argument throw is never
  # forced by the documentation render.
  systemdServiceOptions = buildPackages.nixosOptionsDoc {
    inherit (evalModules { modules = [ ../integrations/nixos/systemd/service.nix ]; }) options;
    # TODO: filter out options that are not systemd-specific, maybe also change option prefix to just `service-opt-`?
    inherit revision transformOptions;
    warningsAreErrors = true;
  };

  # One page rather than one file per chapter: `nixos-render-docs` has no
  # search, so keeping the whole book in `index.html` leaves the browser's
  # find-in-page as the way to look something up.
  manualRoot = pkgs.writeText "manual.md" ''
    # Modular Services {#book-modular-services}
    ## Revision ${revision}

    ```{=include=} chapters
    modular-services.md
    writing-and-reviewing.md
    ```
  '';
in

runCommand "modular-services-manual"
  {
    nativeBuildInputs = [ buildPackages.nixos-render-docs ];
    meta.description = "The modular services manual chapter in HTML format";
    allowedReferences = [ "out" ];
  }
  ''
    dst=$out/${outputPath}
    mkdir -p $dst

    # The NixOS manual's own assets, so the rendered book gets its sidebar,
    # syntax highlighting and heading anchors rather than bare HTML.
    cp ${pkgs.path + "/doc/style.css"} $dst/style.css
    cp ${pkgs.path + "/doc/anchor.min.js"} $dst/anchor.min.js
    cp ${pkgs.path + "/doc/anchor-use.js"} $dst/anchor-use.js
    cp -r ${pkgs.documentation-highlighter} $dst/highlightjs
    cp ${pkgs.roboto.src}/web/Roboto\[ital\,wdth\,wght\].ttf $dst/Roboto.ttf

    cp ${./modular-services.md} ./modular-services.md
    cp ${./writing-and-reviewing.md} ./writing-and-reviewing.md
    cp ${manualRoot} ./manual.md
    chmod +w ./modular-services.md

    substituteInPlace ./modular-services.md \
      --replace-fail \
        '@PORTABLE_SERVICE_OPTIONS@' \
        ${portableServiceOptions.optionsJSON}/${outputPath}/options.json
    substituteInPlace ./modular-services.md \
      --replace-fail \
        '@SYSTEMD_SERVICE_OPTIONS@' \
        ${systemdServiceOptions.optionsJSON}/${outputPath}/options.json

    nixos-render-docs -j $NIX_BUILD_CORES manual html \
      --manpage-urls ${pkgs.path + "/doc/manpage-urls.json"} \
      --revision ${lib.escapeShellArg revision} \
      --generator "nixos-render-docs ${lib.version}" \
      --stylesheet style.css \
      --stylesheet highlightjs/mono-blue.css \
      --script ./highlightjs/highlight.pack.js \
      --script ./highlightjs/loader.js \
      --script ./anchor.min.js \
      --script ./anchor-use.js \
      --sidebar-depth 2 \
      --no-navheader \
      ./manual.md \
      $dst/index.html

    mkdir -p $out/nix-support
    echo "doc manual $dst index.html" >> $out/nix-support/hydra-build-products
  ''
