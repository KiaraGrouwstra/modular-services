
# Writing and Reviewing Modular Services {#chap-writing-and-reviewing}

## Status {#writing-and-reviewing-status}

Modular Services are, as of writing, a new feature with support in NixOS.
It is in development, and be considerate of the fact that the intermediate outcome of RFC 163 is that we should try a module-based approach to portable services; it is not yet a widely agreed upon solution.

## Relation to NixOS Modules {#writing-and-reviewing-nixos-modules}

- A modular service is not a replacement for a NixOS module, but may be in the future.
- Using a modular service to implement a NixOS module is an expected use case, but exposes the NixOS module to a degree of uncertainty that is not acceptable for widely used modules yet.

## Maintainership {#writing-and-reviewing-maintainership}

If you contribute a modular service, you must mark yourself as maintainer of the modular service.
The maintainership of a modular service does not need to be the same as the maintainership of a NixOS module.
If you are not a maintainer of the NixOS module, you should offer to join the NixOS module's `meta.maintainers` team, so that you are included in reviews and discussions, most of which also affect the modular service.
The NixOS module maintainers have no obligation towards the modular service, except perhaps to notify you if they notice that the modular service breaks.

## Minimum Standard {#writing-and-reviewing-minimum-standard}

Modular services **MUST** be accompanied by a **VM test** that exercises the modular service, in at least one integration under [`integrations/`](https://github.com/kiaragrouwstra/modular-services/blob/main/integrations).

Modular services **MUST** have a `meta.maintainers` module attribute that lists the maintainers of the modular service.

## Reviewing Modular Services {#writing-and-reviewing-checklist}

When reviewing a modular service, you should check the following. Details and rationale are provided below.

```markdown
- [ ] Has a VM test, in every integration it claims to support (at minimum `integrations/nixos/tests/packages/`)
- [ ] Registered in that integration's `tests/default.nix`
- [ ] Has a `meta.maintainers` attribute
- [ ] Systemd-specific definitions live in a NixOS variant, not in the service itself, to promote portability.
- [ ] `_class = "service"`
- [ ] Imports nothing from `lib/services`, so that it stays integration-agnostic
- [ ] Has an entry in `modular-services/default.nix` whose `<ns>.package` default comes from the providing package
- [ ] Is the modular services infrastructure sufficient for this service? If one or more features are not covered, comment in https://github.com/NixOS/nixpkgs/issues/428084
- [ ] Has been added to `doc/registry.nix` (enforced by `checks.docs-registry-complete`)
```

## Details {#writing-and-reviewing-details}

### VM test {#writing-and-reviewing-vm-test}

For NixOS, add the test to [`integrations/nixos/tests/packages/`](https://github.com/kiaragrouwstra/modular-services/blob/main/integrations/nixos/tests/packages) and register it in [`integrations/nixos/tests/default.nix`](https://github.com/kiaragrouwstra/modular-services/blob/main/integrations/nixos/tests/default.nix); the surrounding tests there are worked examples.
A test file imports `config.modularServices.<pkg>.<svc>` into the service, so that it exercises the same variant a NixOS configuration gets.
Best practices: keep tests minimal and focused (boot a VM, enable the service, and assert a basic request succeeds). For general guidance, see the [NixOS Tests chapter](https://nixos.org/manual/nixos/unstable/#sec-nixos-tests).

### Integration-specific definitions {#writing-and-reviewing-variants}

A service module under [`modular-services/`](https://github.com/kiaragrouwstra/modular-services/blob/main/modular-services) declares what the service *is*: its options, and `process.argv`.
Anything that only one service manager understands -- unit dependencies, `serviceConfig`, credentials -- belongs to a variant of that service, in the integration that understands it.
For NixOS that is `integrations/nixos/modular/<pkg>/<svc>/`, a pair of files: `default.nix` imports the pure module out of `modularServices.<pkg>`, and `system.nix` adds the systemd definitions.
Register the pair in [`integrations/nixos/modular/default.nix`](https://github.com/kiaragrouwstra/modular-services/blob/main/integrations/nixos/modular/default.nix), as a *path* rather than an `import`, so that the variant keeps its own file attribution; `checks.nixos-modular-variants` asserts that.

Keeping the two apart is what lets a service be loaded into a configuration manager that has no `systemd` option tree at all.
A service that must vary its own definitions per manager can still do so inline, with `lib.optionalAttrs (options ? systemd)`; see [Portability](#modular-service-portability).

### `_class = "service"` {#writing-and-reviewing-class}

A [`_class`](https://nixos.org/manual/nixpkgs/unstable/#module-system-lib-evalModules-param-class) declaration ensures a clear error when the module is accidentally imported into a configuration that isn't a modular service, such as a NixOS configuration.

Provide it as the first attribute in the module:

```nix
# Non-module dependencies (`importApply`)
{ writeScript, runtimeShell }:

# Service module
{ lib, config, ... }:
{
  _class = "service";

  options = {
    # ...
  };
  config = {
    # ...
  };
}
```

### Overriding the package default {#writing-and-reviewing-package-default}

The package option of a service must default to the package that provides the service.
Otherwise, since some packages are *defined* by an override, the modular service would launch a wrong package, if it builds at all.

In this repository a service module is registered in [`modular-services/default.nix`](https://github.com/kiaragrouwstra/modular-services/blob/main/modular-services/default.nix), which supplies both the `importApply` of its non-module dependencies and that default:

```nix
{
  example =
    pkgs:
    {
      imports = [ (importApply ./example/service.nix { inherit (pkgs) formats; }) ];
      example.package = lib.mkDefault pkgs.example;
    };
}
```

`lib.mkDefault` is used throughout, rather than the unpriorised definition nixpkgs uses in `passthru`, so that a configuration can set the package without `lib.mkForce`.

In nixpkgs the equivalent lives in the package's `passthru.services`, and must use [`finalAttrs.finalPackage`](https://nixos.org/manual/nixpkgs/unstable/#mkderivation-recursive-attributes) so that overrides propagate.
That form is still what a service upstreamed into nixpkgs needs.
If it is not possible, or if the module is not represented by a single package, consider exposing the modular service directly by file path only.
