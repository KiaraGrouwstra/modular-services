# Modular service compliance suite

Compliance suite for [modular service](../doc/modular-services.md) integrations.

Tests that a service manager integration correctly handles the portable modular
services contract: `process.argv`, `process.environment` (including `null`
values that unset a variable), sub-services, assertions, and warnings.

The suite is integration-agnostic. Each integration under
[`integrations/`](../integrations) instantiates it once, supplying the four
functions below, and may add its own
manager-specific checks on top; see
[`integrations/nixos/tests/compliance.nix`](../integrations/nixos/tests/compliance.nix)
for a worked example.

## Invocation

```nix
self.lib.mkComplianceSuite pkgs {
  inherit evalConfig mkTest sharedDir callReload;
  namePrefix = "...";
}
```

`mkComplianceSuite` is `pkgs.callPackage ./compliance { }`, so it also works as
a plain `callPackage` target if you are not consuming this repo as a flake.

## Return value

An attribute set of derivations which perform the tests during their build:

| attribute | kind | what it proves |
|---|---|---|
| `eval` | eval | The portable contract holds in the integration's full evaluation context, and `checkDrv` builds. |
| `basic-argv` | vm | A configured service actually runs and receives its `process.argv`. |
| `sub-services` | vm | Nested sub-services run, to a depth of three. |
| `reload` | vm | `callReload` reaches a reloadable *sub*-service, exercising nested unit naming. |

## Inputs

`evalConfig` (function)

: `{ services } -> { config; checkDrv; }`.
  Function to evaluate the given services in the integration's full context.
  This function is called for evaluation checks on configurations that will not be run.
  - Input `services` is an attrset of modular service configurations. These should be used verbatim.
  - Output attribute `config` is the resulting evaluated services attrset (e.g., the value of the `system.services` option in NixOS).
    This attribute must be available even if `checkDrv` would fail.
  - Output attribute `checkDrv` is a representative derivation whose existence and buildability prove the eval is sound (e.g., `system.build.toplevel` in NixOS, but could perhaps be more specific in the case of another process manager integration).
  - The generic tester only reads `config` and `checkDrv`. An integration may return additional attributes for its own integration-specific eval checks. Such extra attributes are optional.

`mkTest` (function)

: `{ name, services, testExe } -> derivation`.
  - Input `name` is a test name, suitable for use as a derivation name.
  - Input `services` is an attrset of modular service configurations, matching the structure of the integration's services option.
  - Input `testExe` is a store path to an executable that verifies the services.
  - Output: a derivation that runs the service manager with the provided configuration inputs and then calls `testExe` after starting the services. That executable must have access to `sharedDir`.

`sharedDir` (string)

: Path to a directory writable by service processes and readable by `testExe`.
  The integration must ensure this directory is available when the services and `testExe` run.

`callReload` (function)

: `path -> string`.
  Given a service's name `path` (the list of service names from the top-level service down to the target sub-service, e.g. `[ "reload" "inner" ]`), returns a shell command that reloads that service.
  The command is embedded in `testExe` and executed with sufficient privilege to reload the service (e.g. as root in the test VM).
  There is no manager-agnostic reload command, so every integration must provide this; the integration joins the `path` per its own unit-naming convention (the suite does not assume one).
  On NixOS the `path` dash-joins into the systemd unit name with a `.service` suffix, so the command is `systemctl reload ${lib.concatStringsSep "-" path}.service` (a top-level service is a single-element path `[ "svc" ]` -> `svc.service`; a nested sub-service `[ "parent" "child" ]` -> `parent-child.service`).

`namePrefix` (string, optional)

: Prefix for the generated derivation and test names. Defaults to
  `"modular-service-compliance"`.

## Example: the NixOS invocation

```nix
self.lib.mkComplianceSuite pkgs {
  sharedDir = "/tmp/modular-service-compliance";
  namePrefix = "system-services-compliance";
  evalConfig =
    { services }:
    let
      machine = evalSystem (
        { ... }:
        {
          system.services = services;
          system.stateVersion = "25.05";
          fileSystems."/" = {
            device = "/test/dummy";
            fsType = "auto";
          };
          boot.loader.grub.enable = false;
        }
      );
    in
    {
      config = machine.config.system.services;
      checkDrv = machine.config.system.build.toplevel;
    };
  callReload = path: "systemctl reload ${lib.concatStringsSep "-" path}.service";
  mkTest =
    {
      name,
      services,
      testExe,
    }:
    runTest {
      _class = "nixosTest";
      inherit name;
      nodes.machine.system.services = services;
      testScript = ''
        machine.wait_for_unit("multi-user.target")
        machine.succeed("${testExe}")
      '';
    };
}
```

## Manual compliance items

The following compliance items are not yet automated and must be verified manually when implementing a new modular service integration.

- **Failing assertions prevent deployment.**
  A service with `assertions = [{ assertion = false; message = "..."; }]` must cause the deployment to fail.
  The mechanism is integration-specific (e.g., NixOS checks assertions during `system.build.toplevel` evaluation).

- **Warnings are visible to the user.**
  A service with `warnings = [ "..." ]` must surface the warning to the user.
  On NixOS these are `builtins.warn` messages emitted during evaluation.
