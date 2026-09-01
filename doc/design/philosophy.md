# Design Philosophy behind Modular Services

This document describes the ideas and architectural decisions that have shaped the Modular Services project.

You'll find many links to prior discussions in this document.
Those were included for completeness, but should rarely be required to be read.

The arguments are cited to where they were made,
which is spread across [RFC 78], [RFC 163], the [proof of concept][poc], the [pull request that landed the subsystem][pr], and the threads that followed.
Most of them were settled in public and can be read there.

## Modularity principles

_The following subsections provide a foundational background for some macro-scale aspects that were already settled._

### Modules, not functions

A module and a function are close to isomorphic.
Inputs map to options,
outputs map to internal options,
several invocations map to submodules,
and a closed-arg function maps to a module that imports little.
The difference is that a function loses the option metadata and the type checking that come with the module,
and it hides its intermediate values in `let` bindings where nothing can inspect them ([RFC 78][rfc78-iso]).

That is why the layer is built out of modules rather than out of functions,
and why designs that reach for functions have been declined rather than adopted.
Sander van der Burg's [nix-processmgmt] discovered a great deal about which options a service description needs,
but its shape was not a perfect match for NixOS because of its sequential functions-based user interface,
instead of the flat fixed-point approach expected from the module system ([meeting notes][meeting-processmgmt], [RFC 163]).

Although functions lack in declarativeness because of their before and after (input and output), the point is not that functions are bad.
It is that a NixOS-like experience wants merging, priorities, `mkDefault`, and options that can be documented and
searched.

Pulling RFC 163's sequence of functions through the isomorphism would not necessarily result in an idiomatic NixOS-like user interface.

### Naming and definition are separate

A service is named by its attribute in an *`attrsOf`* `submodule`, and defined by
what gets imported into it. Those are two jobs, and keeping them apart is what
makes the tree composable ([nixpkgs#372170][pr]).

This is why [`services.<name>.instances.<name>`][instances] was declined.
What that proposal calls a service is a service *module*, and what it calls an instance is a submodule evaluation.
Both concepts already exist as module system primitives,
so encoding them a second time as options means inventing a namespacing system next to the one the module system provides.

The same reasoning rules out collecting every instance in one central attribute set.
Anything an arbitrary function call can do can be done by importing into a submodule,
and a central registry of instances is not modular in the first place ([RFC 163][rfc163-imports]).

## What the core contains, and what is only missing

As of writing, `lib/services/service.nix` declares
`services`, `process.argv`, `process.flags`, `process.flagFormat`, the two reload options, and `notificationProtocol`.
That is the whole portable commitment, plus `configData` and the `assertions` and `meta.maintainers` modules.

Some of what is absent is absent on purpose. There is no `enable` option,
because it would be ambiguous between generating nothing at all and generating a
disabled unit, and a service is on by existing in the `attrsOf`
([nixpkgs#372170][no-enable]). `systemd.packages` is out of scope, because
prefixing unit names from a package's own units cannot obviously be done
reliably and it replaces the process options anyway.

Most of what is absent is simply not built yet.
For instance, users, directories, files initialization/cleanup rules and port metadata are missing because nobody has written them,
not because anyone decided a service should do without.

<!-- not sure where to put this one -->

`configData` is portable, and exists to make reload without restart possible.
That needs a stable path rather than a store path that changes on every rebuild
but gets frozen into the process invocation
([nixpkgs#430490][configdata]).
Its `path` is typed `str` rather than `path`,
so that an integration can hand back a relative location and stay unprivileged or relocatable.

## Isolation: not facilitated, rather than prevented

A service module is evaluated in a submodule, which gives it a degree of isolation, where "degree" does some heavy lifting.
While the Module System and the service manager integration are expected not to pass information about a host system to the service modules,
an individual module can be given any information about the host system or whatever else, as long as the user facilitates that.
This includes means such as the lexical scope (including `importApply`) and any file it can name.
So this is not quite a sandbox.

What the design does instead is decline to hand the ambient world down.
A service manager integration is strongly discouraged from exposing host-global information through module arguments or options,
so that it does not poke unnecessary holes in hermeticity and portability.

It is discouraged, not stopped.
Someone writing a module in their own configuration would do well to follow the same principle,
but can not be forced to, and they may well *need* to reach for information their lexical scope holds (e.g. the containing NixOS host),
so even if such a rule were implementable, it is not desirable for user modules, and the module system does not discern user vs integration vs built-in modules.
That is their choice to make, and their choice will be clearly visible in their own code.
Explicit is good.

Removing the `pkgs` module argument is a clear instance of this principle ([nixpkgs#435092][no-pkgs]).
It was not removed because a service must never see a package set.
It was removed so that the framework stops supplying the host's one,
which is what creates ambiguity about which nixpkgs a service is coherent with,
and what quietly complicates or rules out mixed-versions deployments.
A service that wants a package set says `_module.args.pkgs = pkgs;` in one line, or names its
dependencies through `importApply` and gets exactly those. Both are explicit,
and both are the caller's decision rather than the framework's.

The other direction is more constrained, and genuinely so.
A service module's definitions do not merge directly into the configuration that hosts it.
It cannot write to `/etc` or create a user unless the integration reads that intent out of the submodule and acts on it ([RFC 163][least-authority]).
Reading the surroundings is unfacilitated;
affecting them is impossible without the integration's cooperation.

## Older principles, carried over on purpose

Coexistence, hermeticity, isolation and [interface segregation][isp] all predate this subsystem,
and a good deal of the design is inspired by those principles.

These are the choices that make Modular Services worthwhile, but they were not forced.
Nothing about service management inherently requires any of them.
A service layer that ignored coexistence would evaluate perfectly well,
and most distributions ship exactly that.
In fact, that includes NixOS.

The decision is that a service should feel like the rest of Nix,
which is to say that these properties are architected into the system
instead of leaving them entirely for users to solve.

Take **coexistence**.
Two versions of a package sit in the store at once and neither has to negotiate with the other.
Services were made to work that way because making every application that needs a database agree on one version is unnecessary and can be problematic,
and having to agree at all sits badly with the rest of Nix ([RFC 163][coexist]).
Hence a service that is instantiable more than once *by construction*,
and an application that can carry its own database as a sub-service rather than queueing for the host's single one.
The singleton is what that chooses against: today there is one postgresql and you get separate logical databases inside it ([nixpkgs#428084][singleton]).
The ambition was put well on RFC 163, that multiple instances should be as effortless as the store makes multiple versions of a package ([RFC 163][effortless]).

Leaving `pkgs` out is the same choice one level further out.
A service that is not handed the host's package set lets a deployment mix nixpkgs versions,
instead of every service on a machine agreeing on one.

Leaving that out also creates a sense of **hermeticity**.
A service is determined by its declared inputs:
`importApply` names them, so `easytier` asks for `formats`, `bash` and `iproute2` and gets those three,
and the framework was built to provide no implicit dependency injection.

**Isolation** is what a container system achieves, but applied here more as an abstract concept or guiding principle.
Modular Services does not directly implement a security mechanism at the runtime level,
but relies on the Nix store to provide coexistence (which could be considered weak isolation),
and relies on the pure Nix language and the module system to facilitate a degree of local reasoning.
Not syntactic local reasoning, but at module scale, by having the design aim for hermeticity.

A service's definitions affect nothing outside the submodule unless the integration acts on them.
This is can be seen as a cost in the choice of data model.
aanderse put the objection well: NixOS is useful partly *because* a module can touch any part of the system,
and a web application module reaching its database, cache and reverse proxy is the normal case rather than an abuse
([RFC 163][isolation-cost]).

Portability and modularity are independent axes, and portable *system* modules
are a coherent idea that simply is not built here. finix already sets
`class = "nixos"` for a degree of informal portability at that level. Leaving
system-level portable modules out is a prioritisation, not a judgement that the
idea is wrong.
In this regard, our focus is on modular and portable *services*, not portable **system modules**.

What the objection is useful for is showing a difference in data model. A
service module describes a service, and its effects on the host and on the
service manager are meant to be limited and mediated.
For instance, arbitrary files in `/etc`, or installing commands system-wide into `$PATH`, do not fit that,
and the reason is coexistence again:
unlike store paths and container images, those things collide.
Two instances of a service cannot both own `/etc/foo.conf`.

So the answer is not to forbid the capability but to offer a shape that does not collide.
An integration can give a service a fixed prefix inside `/etc` derived from its attribute path,
or a shell profile named the same way.
*Unmediated claims about the system belong in the system configuration rather than in the service configuration*.

Interface segregation shows up wherever a narrow thing is handed over instead of
a broad one, and twice with the reason written down. `escapeSystemdExecArgs` is
exposed as `systemd.functions.escapeShellArgs` rather than through NixOS's
`utils`, to avoid making the code more NixOS-specific than necessary and to
avoid handing service modules a broad `utils` they would then abuse
([nixpkgs#372170][escaping]). And a service that needs `formats` and `bash` is
given `formats` and `bash`, which is the same principle applied to the argument
that used to be `pkgs`.

## Waiting was the strategy, and the waiting is over

The portable set was deliberately left thin at first.
Designing it before there were services to test it against invites over-engineering or analysis paralysis,
and the module system tolerates a leaky abstraction well enough to make the wait affordable ([nixpkgs#430490][merge-rationale]).
The RFC was closed for the same reason: by growing the implementation the open produces, we produce the input that is needed for the interface decisions,
where the document was producing argument instead ([RFC 163][rfc163-closed]).

That was a phase, not a permanent stance, and it has ended.
The lowest common denominator was always meant as a starting point rather than as the design.
The intended way to improve on that is with shims, feature checks and assertions,
rather than settling for perfect-or-nothing
(argued in [the Matrix room][room], 2026-05-11).
There are real services now, so the reason for waiting is spent.

The [staged plan][roadmap] says so directly.
Stage 1 caps merged services at twenty,
requires maintainer buy-in,
and forbids NixOS modules from depending on them,
while adding portable options, user support and the registry.
Stage 2 opens up services and contracts.
Stage 3 lets NixOS modules depend on modular services and moves the feature from experimental towards stable.
The cap is there to stop conversions consuming the attention the interface needs,
and to limit the impact of breaking interface changes.

The work is already visible. `process.environment`, `flags` and `flagFormat`, and the reload options have landed.
`process.runtimeDirectory` is in progress,
user-level services and reload on `configData` change are waiting on review,
and the user model has a design aligned with this design philosophy document:
each service gets its own user derived from its place in the sub-service hierarchy,
a service declares only that it *shares* another's user,
and configuration managers without users ignore it ([nixpkgs#545287][users]).

## Every escape hatch has a name

The alternative design, a portable service layer with no service manager specific options inside the submodules, was considered and rejected.
It has no escape hatches, which makes it a poor fit for growing something incrementally
(argued in [the Matrix room][room], 2026-05-17).

So escape hatches are expected, and they are treated well.
We do not cover up and "undocument", because that just covers up [Hyrum's law] at the cost of users.
That would have been bad enough as-is, but inexcusable when we know the escape hatches are needed.

Example:
`systemd.mainExecStart`, `systemd.mainExecReload` and `systemd.lib` are typed options with documentation.

There is no `extraConfig` string at the framework level, and the
only freeform surfaces are a service's own `settings`.

## Avoid implicit functionality

`systemd.mainExecStart` is the source of truth for what a systemd integration wires into the system.
It defaults to the *escaped* form of `process.argv`,
so that a service must explicitly ask for systemd specifier substitution instead of something it gets without choice,
or without warning when this presumed "`process.argv` functionality" is missing on other service managers.

Simply put: literal arguments stay literal
([nixpkgs#469450][mainexecstart]).

## Declare a difference rather than hiding it

Note that wee are considering alternatives for this `options ? ...` approach, such as letting the service manager integration extend the module set ([nixpkgs#540863]).
The following two paragraphs describe the status quo.

Portability here works by feature detection on the definition side.
A service wraps its systemd definitions in `lib.optionalAttrs (options ? systemd)`,
and they are ignored where that option does not exist.
The `php` service keeps a dormant `options ? finit` branch for the same reason.

This is deliberately not an abstraction that papers over the managers. It is a
way for a definition to say what it knows about, and for the parts it does not
know about to fall away.

The principle of declaring differences also decides smaller questions.
Readiness is modelled as a negotiation in which the service says which notification dialect it can emit
and the manager says which it can handle (argued in [the Matrix room][room], 2026-06-02).
`notificationProtocol` stays a closed enum rather than one each manager extends,
because an extensible enum forces a portable service to add conditionals purely
to avoid offending a manager that has not heard of the other protocol
([nixpkgs#535695][enum]).
The compliance suite requires every integration to supply `callReload`,
because there is no manager-agnostic reload command
and inventing a plausible one would be worse than admitting the gap.

## Priorities for deciding conflicting choices

When two of these pull against each other,
the order is clarity first,
then failing safe,
then the convenience of writing a service,
and last the convenience of integrating a service manager
(stated in [the Matrix room][room], 2026-06-02).

The integrator coming last is not an oversight.
It is why `callReload` is a required parameter,
and why a `reload.command` that quietly defaults to a derived value was declined:
an integration would have to inspect `options.reloadCommand.highestPrio` to work out whether the default still stood,
and that is a worse thing to ask of it than writing one more line.

Failing safe shows up in the assertions.
For example, we have detect a conflict when a user has set `reloadCommand` explicitly alongside `reloadSignal`,
but not when one derived the other.

`configData.<name>.source` has no default, so setting neither `source` nor `text` is an evaluation error;
not a broken default like an empty file.

Clarity is why we aim to specify all corner cases.
Every detail of an interface gets depended on eventually,
so for instance, `reloadSignal = null` is explicitly specified as no signal is ever sent.
If left as a choice to the service manager, that leads to avoidable differences in behavior
([Discourse][null-meaning]).

## Modularity and portability, both

Modularity is the ability to import any piece of service logic under any service name,
and to group services into one service with sub-services.
It is the raison d'etre for modular services, and it is an aspect that is finished,
and worth having on its own.

Portability is the younger half and has fewer of its problems solved.
Today the inherently portable options are `process.argv` and the sub-services option,
and everything else is either integration specific or waiting to be generalised
([nixpkgs#430490][modularity-portability]).

Treating that as a reason to drop portability would be the wrong read.
People want it, they are building against it ([NixNG][nixng], [nix-darwin][darwin]),
and their reports are the most useful evidence available about which options belong in the portable set.
The two goals are at different stages,
and stage 1 of the plan exists to close the gap rather than to live with it.

What does need fixing is faux portability:
a service that evaluates anywhere and is broken or insecure outside of systemd.
The intended answer is for a module to declare which platforms it supports,
so the failure arrives at evaluation rather than at runtime ([nixpkgs#540863][faux]).
That work has not been done yet,
and until it is,
the floor of the interface fails open while the priority order says it should fail safe.

<!-- footer-style markdown links for the document above -->
[RFC 78]: https://github.com/NixOS/rfcs/pull/78
[RFC 163]: https://github.com/NixOS/rfcs/pull/163
[poc]: https://github.com/NixOS/nixpkgs/pull/267111
[pr]: https://github.com/NixOS/nixpkgs/pull/372170
[rfc78-iso]: https://github.com/NixOS/rfcs/pull/78#discussion_r545685380
[nix-processmgmt]: https://github.com/svanderburg/nix-processmgmt
[meeting-processmgmt]: https://discourse.nixos.org/t/78235
[instances]: https://github.com/NixOS/nixpkgs/pull/372170#discussion_r1985443422
[rfc163-imports]: https://github.com/NixOS/rfcs/pull/163#discussion_r1348841973
[no-enable]: https://github.com/NixOS/nixpkgs/pull/372170#discussion_r1907622049
[configdata]: https://github.com/NixOS/nixpkgs/pull/430490
[merge-rationale]: https://github.com/NixOS/nixpkgs/pull/430490
[no-pkgs]: https://github.com/NixOS/nixpkgs/pull/435092
[isp]: https://en.wikipedia.org/wiki/Interface_segregation_principle
[coexist]: https://github.com/NixOS/rfcs/pull/163#issuecomment-1887165651
[effortless]: https://github.com/NixOS/rfcs/pull/163#discussion_r1382541592
[singleton]: https://github.com/NixOS/nixpkgs/issues/428084
[isolation-cost]: https://github.com/NixOS/rfcs/pull/163#issuecomment-2297641245
[escaping]: https://github.com/NixOS/nixpkgs/pull/372170#discussion_r2059860905
[least-authority]: https://github.com/NixOS/rfcs/pull/163#discussion_r1390470473
[rfc163-closed]: https://github.com/NixOS/rfcs/pull/163#issuecomment-2573549371
[roadmap]: https://discourse.nixos.org/t/79145
[users]: https://github.com/NixOS/nixpkgs/issues/545287
[room]: https://matrix.to/#/%23modular-services:nixos.org
[mainexecstart]: https://github.com/NixOS/nixpkgs/pull/469450
[enum]: https://github.com/NixOS/nixpkgs/pull/535695
[null-meaning]: https://discourse.nixos.org/t/78847
[modularity-portability]: https://github.com/NixOS/nixpkgs/pull/430490
[nixng]: https://github.com/nix-community/NixNG/issues/67
[darwin]: https://github.com/nix-darwin/nix-darwin/pull/1765
[faux]: https://github.com/NixOS/nixpkgs/pull/540863
[Hyrum's law]: https://www.hyrumslaw.com/
[nixpkgs#540863]: https://github.com/NixOS/nixpkgs/pull/540863
