----------

Links
- [GitHub Project Board](https://github.com/orgs/NixOS/projects/116)
- [Matrix](https://matrix.to/#/#modular-services:nixos.org)

----------

<!-----------
past meetings
------------->


# modular services meeting 2026-05-26

<details>
<summary>
    
Posted: https://discourse.nixos.org/t/modular-services-meeting-1-2026-05-26/77846

</summary>
    

### lassulus ideas (written up before meeting)

- want to expose services (for long running packges)
- wants to support wrapped packages (for long running and short running packages)
- wants to map execve as a very small base layer https://man7.org/linux/man-pages/man2/execve.2.html
    - basically everything uses execve under the hood
    - we can add additional stuff around it that basically maps to execve later on
- we should start small and expand later (out of tree experiments are fine)
    - for the beginning only systemd and wrapper support

### meeting minutes

- status: for now keep things experimental, should find what works rather than get stuck on bad interfaces
- contracts?
  - don't need to abstract over package differences
- negative feedback at tracking issue, modular services thread
  - tried to better explain at tracking issue and by reaching out
  - one concern seemed preventing doing a flakes, tho to get things going we need to attract contributors too
- how do services relate with e.g. databases?
  - implicit like in nixos? -> default to sub-services
  - explicit? -> contracts, potentially between nodes
    - e.g. k8s likes to see services separately to know what's healthy vs what failed and needs to be brought up again
  - -> status: needs more experimenting
- manual entry
  - add link to matrix channel + tracking issue?
- idea on renaming to package modules
  - no objections, mostly a documentation thing
  - wrapper PR rebasing TODO@lassulus
- how to extract options
  - maybe don't
  - get it from pkg.modules.default etc
  - `mynginx = { imports = [ nginx.modules.default ]; options.....; }`
- kiara: should we not separate generic services modules vs system-specific ones (living in the systems' repos)? cuz these need system-specific options
  - aanderse: then what's the value proposition for consuming systems like finix? get the data model correct in nixpkgs, e.g. on reloading.
  - kiara: would robert's idea of shims address this concern, adapting to a given system based on the info exposed in a modular service?
  - aanderse: potentially yes
- modular services option set:
  - aanderse: we should expand what we offer, not every implementation needs to use every option
  - let's add a reload command as well as a notification protocol
- meeting cadence:
  - attendants found this meeting useful
  - let's try every 2 weeks
  - TODO@lassulus make new crabfit
  - TODO@lassulus add to official calendar (and link it in the matrix)
- action items
  - [~] provide more info to other service managers
  - roberth: finish platform-generic "compliance" test
  - [ ] roberth: review `environment` PR
  - kiara: continue on PRs
    - [x] environment
    - [ ] docs
    - [ ] user-service
  - [x] roberth: post meeting notes to discourse

</details>

# modular services meeting 2026-06-12

<details>

<summary>
    
Posted: https://discourse.nixos.org/t/modular-services-meeting-2-2026-06-12/78235

</summary>

- @Eveeifyeve: been working on this serviceManager API, got a branch up
- @tomberek: we should be aware of @svanderburg's earlier work, RFC 163, nix-processmgmt
  - @roberth: i've been aware of it, and he discovered many of the options we might want, tho he and i agreed his wasn't very NixOS-like (many functions), so we should adapt the concepts
- @Eveeifyeve: php-fpm's adaptations to different environments (NixOS, finix) could just use shims

- @kiara: Are we modeling a lowest common denominator
- @aanderse: I think we're modeling various information attributes
- ?: risk of playing favorites
- @kiara: if we wanna support environment-specific stuff, will we get one giant frankenstein interface? or keep to info useful to multiple environments?
- @roberth: environment-specific interfaces could just help for consistency (rather than as an abstraction)
- @kiara: how do we avoid just wrapping environment-specific options then?

- @tomberek: what about other use cases?
- [weyl nimi](https://discourse.nixos.org/t/portable-rust-based-service-runner-for-the-experimental-modular-services-spec/74338)
- @aanderse: how would k8s fit into the picture: k8s can use MS or MS supports k8s?
- @kiara: I'm interested in this use case. It fills a gap between NixOS and k8s. Experimenting with this for Fediversity
- @tomberek: distributed systemd is something I would expect to evolve in the ecosystem at some point
- @kiara: ~~Kelsey Hightower when talking about about the gap between NixOS vs Kubernetes mentioned having done CoreOS before~~ - looks like that wasn't actually distributed, never mind
- @aanderse: I don't think systemd has those ambitions. Nomad was closer to what you're talking about, but wasn't a viable k8s - abandoned (+ switched to BSL)
- @roberth: a missing ingredient for this kind of thing is mutable units
- @aanderse: deploy-rs may support or consider this
- @aanderse: we could support evaluating systemd units based on modular services. Small amount of work to support this use case
- @aanderse: finit supports ad hoc services in /run too.
- @tomberek: decoupling of infrastructure and control plane is helpful. Disnix also did this nicely
- @aanderse: doesn't model cross-service interactions between the mutable part and the system part
- @tomberek: nixos-containers could be part of the pattern here. Coupled things go into your infra layer, and the rest can go into the container-based service layer. The layers are declared independently.
- @aanderse: @phaer is doing some cool work on decoupling in NixOS.
- @EveeifyiEve: any blockers for integration with NixBSD?
- @aanderse: They're interested, no active efforts to start integrating so far. They also have a different finit integration.
- @EveeifyiEve: what other integrations are missing that would help people? e.g. dev-env, services-flake, nixbsd
- @aanderse: Those are all valid gaps to fill, but we should focus last meeting's plan.
- @roberth: Not before we've figured out a number of options
- @roberth: here's a branch for testing modular services in a portable fashion: https://github.com/NixOS/nixpkgs/compare/master...roberth:nixpkgs:modular-services-compliance-suite
  - @kiara: use NixOS test container stuff
  - @kiara: could we generalize this to a test framework that service module authors can use?
  - @roberth: perhaps, but I didn't consider it in scope for now

### Housekeeping

- @aanderse: Meeting is biweekly
- @aanderse: Let's avoid analysis paralysis. For instance, backcompat is not a concern

- actions
  - async: answer @eveeifyeve's questions
  - [ ] roberth: finish platform-generic "compliance" test
  - [ ] roberth: review `environment` PR
  - kiara: continue on PRs
    - [ ] docs
    - [ ] user-service
  - lassulus: continue on flags PR

</details>

# modular services meeting 2026-06-26

<details>

<summary>
    
Posted: https://discourse.nixos.org/t/modular-services-meeting-3-2026-06-26/78582

</summary>


Attendees: @EveeifyiEve, @lassulus, @roberth, @aanderse

## Sync

- @EveeifyiEve has worked on [code changes](https://github.com/NixOS/nixpkgs/compare/master...DigitalBrewStudios:nixpkgs:modular-service-generalization-service-api) from previous meeting, @aanderse likes and thinks this is the right direction
- @roberth has done some work on a generic test suite to be used with modular services
    - ready for merge https://github.com/NixOS/nixpkgs/pull/531062
- @lassulus finished work on PR adding flags
    - https://github.com/NixOS/nixpkgs/pull/509595
- @Evee: what's the community working on?
    - @aanderse: @ehmry was doing some work on a platform that would be solely modular services based, s6 / runit style stuff. Lower level so not sure if I would recommend looking at that
    - @aanderse: we could create a repo in nix-community, lower stakes where people can contribute easily. Having a lot of them in nixpkgs is not quite right yet
    - @aanderse: @artemist has started work on a BSD implementation :tada:

## Review https://github.com/NixOS/nixpkgs/pull/535695

Adds generalization support for reloading, readiness and runtime directory.

New options
- `reloadSignal`
    - @aanderse: seems unused
    - @evee: not sure what @roberth wanted
    - @roberth: reloadCommand defaulting to signal should be fine
    - @roberth: we should specify what happens when both are specified. I'd lean towards forbidding by means of assertion
      - something with `options.reloadCommand.highestPrio == optionDefaultPrio`
- `reloadCommand`
- `runtimeDirectory`
    - @roberth: It's not clear to me who is supposed to set this, e.g. systemd vs user (probably not module author)
    - @aanderse: We had this idea where options are about declaring the intent of a module
    - @aanderse: Only systemd supports this out of the box. Other service managers [integrations] can fill the gap if they need to
- `runtimePermission`
- `serviceManager.notificationProtocol`
    - @roberth: I would expect this option path to say "the service manager supports this protocol (/ maybe *these* protocols)
    - @aanderse: with finit we *might* want to expose what we support
    - @aanderse: I'd move it to top level because it's about the service itself. I'd punt on the service manager introspection until we have a real need
    - @roberth: I agree
- `serviceManager.preserveRuntimeDirectory`

Implementation
- @aanderse: setting `Type` there is nice
- @roberth: `mainExecReload` is analogous to `mainExecStart`, allowing `systemd`-specific escape hatch for `%n` interpolation support

Please split out `runtimeDirectory` so we can settle the reload options sooner



## Action items

- [ ] roberth: review `environment` PR
- [ ] lassulus: flags
- [ ] aanderse: will port new options to finit when done
- [ ] evee: implement review feedback

</details>


# modular services meeting 2026-07-10

<details>
    
<summary>

Posted: https://discourse.nixos.org/t/modular-services-meeting-4-2026-07-10/78847

</summary>

Attendees: @eveeifyeve @roberth, @artemist, @kiara, @aanderse


- @eveeifyeve: Should we create a team?
- @roberth: Yes, and I can do it. But we need a name.
    - @roberth: Not sure if package modules is exactly the right name. We have three concepts that are quite distinct, and *two* give rise to the name "package module"
        - derivation
        - package (attrset)
        - package runtime configuration
    - @roberth: Maybe the formal name should be "package usage module" or "package runtime module", but then informally we'd still call them package modules
    - @roberth: Or should we rename them to "runtime modules" - short, distinct and meaningful
    - @eveeifyeve: I am not really sure about the naming probably best to ask in a future meeting.
    - @roberth: agreed

- @eveeifyeve: It would be good to have a followup review from @aanderse to do the following touches as I have responded to previous review. 
    - @roberth: Would be good to make the meaning of the `null` values completely explicit. Kind of like [Hyrum's law], every detail will be depended on, so we should avoid any ambiguities about it.
    - @roberth: My *guess* for `reloadSignal` would be that `null` means never send a signal. Otherwise that's not representable. Leaving the choice of signal to the service manager would be a bit chaotic. Would be good to have @aaronanderse input on this.
    - @roberth: For `reloadCommand`, similar. If both are unset, the service does not support reloading. Should a service manager fall back to restarts or just leave the old service running? This should become an option. Could postpone - not in this PR.
    - @eveeifyeve: Agreed, It would be great to have @aaronanderse input, as I am not sure.


- @eveeifyeve: Progress on the `process.environment` pr, as it would be useful for the [database modular services flake] I am creating.

- @eveeifyeve: Would it be good to have a wrapper function for making search.nixos.org backend responsible for combining the NixOS and service option  that wraps the ability to define the modular services, disable the docs and options?
    - @roberth: @Ericson2314 did some initial work on this in https://github.com/NixOS/nixpkgs/pull/475372
        - Uses `mkAliasOptionModule`
        - Probably adversely affects documentation

- @eveeifyeve: Wondering how the progress on adding Modular Services to nixbsd, as I have made a review regarding testing as there was a merged pr regarding testing modular services and I was wondering if there is more help needed.
    - @roberth: I noticed NixBSD switched their `class` to `nixos`, which is interesting. Not what I imagine, but if they can pull off decent NixOS option compatibility, that's great!
    - *@artemist joins* (by great coincidence)
    - @artemist: ...
    - @artemist: What would be possible to move in tree into nixpkgs?
        - @artemist: e.g. could we put a core freebsd service configuration in `pkgs/os-specific/bsd`
            - Would still rely on option definitions in external repo
        - @artemist: Modular services helps add new content to NixBSD, but was never designed to ease the maintinence burden
        - @artemist: a "Maximum Modular Services" would involve splitting services into a modular part and a non-modular part, e.g. sshd service and config in modular services, pam outside.
        - @artemist: I think the biggest issue is the modules in nixpkgs. 
        - @robeth: We already have some nixos extentions already, e.g. you can query `options?systemd` and then let your module do more.
        - @artemist: The problem would be the hack usage of tmpfiles.
        - @roberth: tmpfiles usage in NixOS is a bit weird. I feel like we could do better
    - @artemist: NixBSD could implement VM tests for `testers.modularServiceCompliance`
    - @eveeifyeve: Could be nice to have Darwin VMs in the future, but would be unfree
        - @artemist: Only 2 VMs at a time limit. Windows has no limit for 11 Pro and higher-end Server
    - @eveeifyeve: Many proejcts have separate module systems (e.g. NixOS, NixBSD, new [nix-windows] which I am working on), keeping compatibility is challenging
        - @artemist: NixBSD borrows modules directly from NixOS, but that creates its own challenges
    - @artemist: The Maximum Modular Services idea would be interesting to try out
        - @roberth: Global modules are inherently different than composable ones, could split on that ground, perhaps in different files
            - Globalness is a `_class` thing. Splitting into file could be a different or combined solution strategy
        - @artemist: Multiple files could be good, makes it easier to import into NixBSD and future configuration systems
        - @roberth: Could also keep everything in `_class = "nixos"` system-level, but split system by file
        - @roberth: Could also use mix-ins and have different OSes define their own mapping to their system config, e.g. https://github.com/NixOS/nixpkgs/blob/c76669e14e57cc9236097e862aff8f1d0e25ecf0/nixos/modules/system/service/systemd/system.nix#L65
        - @artemist: Try out a few approaches, see what works
    - Some discussion about config portability
        - @roberth: Translating upstream systemd units is not entirely impossible, but would be complex. I think our current course for portability is good
    - *@artemist left*
    - *@KiaraGrouwstra joins*
    - @KiaraGrouwstra: I have architectural concerns about `notificationProtocol`, as it has details for arbitrary service managers whereas `lib` should be agnostic
    - @roberth: Could use extensible `enum` pattern
    - @eveeifyeve: It should be a list
    - @roberth: It's needed by the systemd logic because systemd needs to know whether to expect a response from the service.
    - @roberth: Backtracking on extensible enum because it makes service definitions unnecessarily hard because it would have to add conditionals not to "offend" the service manager with unknown values.
    - We reached the decision to allow this enum, which models a service property that's largely independent of service manager implementation. (Protocols are a "small waist" even if it's multiple ones)
    - *@aanderse joined

- Followup: 
    - [ ] Mention the distincintion about Package Modules.
    - [ ] @aanderse Followup with a review on https://github.com/NixOS/nixpkgs/pull/535695

[Hyrum's law]: https://www.hyrumslaw.com/
[database modular services flake]: https://github.com/DigitalBrewStudios/Database-Modular-Services
[nix-windows]: https://github.com/DigitalBrewStudios/nix-windows

</details>

# modular services meeting 2026-07-24

<details>
    <summary>

Posted: https://discourse.nixos.org/t/modular-services-meeting-5-2026-07-24/79145

</summary>
Attendees: @aanders @KiaraGrouwstra @eveeifyeve @roberth

- @KiaraGrouwstra: should we be using upstream files?
    - @aanderse: NixOS should do this, it does, which is good, but generally we ship a lot of opinion on top of those
    - @Kiara: emilazy was interested in this argument for nix-darwin
    - @roberth: this approach wouldn't support multi-instance modularity
- @Evee: tmpfiles. Multiple implementations exist. I'd like to make that portable. Not sure about implementation detail
    - @roberth (prior on matrix): not a fan of the syntax
    - @aanderse: it seems that the open source world has agreed that doing this through some files is more robust than shell scripts. Worth discussion. Alternatives exist
    - @roberth: very helpful if we could pass a file name to the tool, because a system-wide tmpfiles doesn't run right before switch, when it needs to
    - @aanderse: RuntimeDir is obviously tied to lifecycle, but state directories traditionally not necessarily, but I think there's value in it
    - @aanderse: To a critic who doesn't want tmpfiles, what do we tell them?
    - @evee: They don't have to use it, like you wouldn't use a non-portable C function
    - @aanderse: Then perhaps we don't need to cover it in the modular service interface, and an implementation can choose to provide/use tmpfiles or not
    - @evee: What should the interaction with user permissions look like?
    - @aanderse: I wouldn't mind systemd's API
    - @roberth: User management is somewhat of a prerequisite for file system stuff
- @KiaraGrouwstra: what do we think of the approach of platform-specific modules?
    - @roberth: makes composition harder
    - @Kiara: new `modularServices` option can solve that
    - @roberth: agreed, reminds of overlays
    - @Kiara: how do we build this out
    - @roberth: maybe call it registry? Kind of like a package set, but of modules.
    - @roberth: could reuse the by-name infrastructure?
    - @Kiara: no strong opinion on file location, pkgs/by-name would be a layer violation
    - @roberth: claim a top-level dir? The portable parts are between the packages layer and NixOS layer
    - @roberth: so portable parts go into pkgs, possibly by-name, NixOS parts go into nixos/
    - @Evee: I think we should still focus on building out the portability through options
    - @roberth: agree, but the registry is simple and has value of its own
    - 
- @KiaraGrouwstra: on sub-services, I'd like to have something like contracts
    - @roberth: absolutely, can do both, and multi-service package should be a two-layer activity: contract-based first, modules that compose those on top. Users can choose.
- @KiaraGrouwstra: what do we prioritize. E.g. people are creating services. Maybe we need to focus on our capabilities first. Some PRs have been open for a while. How do we prioritize? What are values based on which to review and decide?
    - 
- Pr Reviews
    - https://github.com/NixOS/nixpkgs/pull/475372
        - still prototype stage
        - @roberth: liability could be a problem at this stage, modular services becomes load bearing for NixOS (first time)
- @KiaraGrouwstra: what are our priorities and shape of roadmap
- @KiaraGrouwstra: maybe one for me would be outstanding question marks
    - e.g. around [child services and contracts](https://github.com/NixOS/nixpkgs/issues/490688)
- @aanderse: i'm just here to advise from the perspective of an external existing system
    - few services, i doubt anyone is depending on this already
- @roberth:
  - Need to solve a number of pain points before significantly expanding set of services, let alone allowing NixOS to depend on them
    Perhaps:
    - Stage 1:
        - do not merge more than 20 modular services, require maintainer buy-in, no usage in NixOS modules (ie need duplication)
        - add more portable options
        - make it reasonably secure on NixOS: user support
        - add the registry
    - Stage 2:
        - allow more services, allow different person than package/NixOS maintainer to maintain modular service
        - keep building out portable options
        - solve other pain points
        - contracts
    - Stage 3:
        - allow use by NixOS modules
        - experimental -> stabilizing
    - Stage 4: profit

- @Evee: put growing NixOS services on hold until this gets more mature (in terms of portability APIs), now trying to make a modular service for a database
- @KiaraGrouwstra: if we got ideas on TODOs let's file them in the issue tracker for the kanban
    - @roberth: ok i'll file one on service users

- @roberth: opened https://github.com/NixOS/nixpkgs/issues/545287

We did a bit of work session after the meeting.
We have a [label](https://github.com/NixOS/nixpkgs/issues?q=label%3A%226.topic%3A%20package%20configuration%20modules%22) and a [board](https://github.com/orgs/NixOS/projects/116/views/1) now :tada:
</details>



# modular services meeting 2026-08-07

<details>
<summary>
    
Posted: https://discourse.nixos.org/t/modular-services-meeting-6-2026-08-07/79408
    
</summary>

Attendees: @aanderse @kiaragrouwstra @eveeifyeve @roberth + 3 guests

- @eveeifyeve: apologies for my PR. What is the status of CI?
    - @kiaragrouwstra: downstream consumers make it harder still, e.g. the problem with home manager using our Nixpkgs stuff in an unanticipated way
    - @eveeifyeve: could we have more eval tests in lib?
    - @kiaragrouwstra: that only gives limited coverage. Couldn't we test it more in a Nixpkgs context?
    - @roberth: I think we need to figure out with CI how to trigger the right reverse dependencies
    - @lassulus: We don't have any capability to run NixOS VM tests in GHA or nixpkgs-review
    - @roberth: We could at least test a *different* service manager that doesn't require virtualization. That would give us coverage of the portable stuff and a large part of the compliance suite
- @eveeifyeve: **contracts**, could we make a portable api to it that's not NixOS-specific
    - @kiaragrouwstra: it wasn't NixOS-specific
    - @eveeifyeve: I was wondering about ibizaman's PR
    - @kiaragrouwstra: his initial work was NixOS-specific, but I've made it portable
    - @eveeifyeve: would be good for e.g. secrets
    - @kiaragrouwstra: this would need some code duplication because NixOS and modular services have different option spaces
    - @eveeifyeve: defining secrets across multiple hosts is challenging
    - @kiaragrouwstra: duplication is probably solvable but we needed to start out simple
    - @kiaragrouwstra: for fediversity I use openbao and a vars-like mechanism with contracts
    - @lassulus: vars is in good state for NixOS, could be made portable in followup
        - https://github.com/NixOS/nixpkgs/pull/547171
    - @kiaragrouwstra: https://github.com/NixOS/nixpkgs/pull/503858
    - @kiaragrouwstra: not even NixOS has solution, so not sure this is in scope for modular services?
    - @eveeifyeve: it is a blocker for databases

- @roberth: package modules, status update?
    - @lassulus: side tracked past month
    - @kiaragrouwstra: I used the term in the docs PR as well
    - @eveeifyeve: what changes?
    - @kiaragrouwstra: just the name, and more widely usable
    - @eveeifyeve: would appreciate more reviews on https://github.com/NixOS/nixpkgs/pull/546008

- @eveeifyeve: relevant for nix on windows too
    - @kiaragrouwstra: what is the status of that?
    - @eveeifyeve: me and @tomberek have been working on a prototype
    - @eveeifyeve: I'd like to work on a stdenv for mingw

- @eveeifyeve: how's progress on user creation
    - @roberth: none yet
    - https://github.com/NixOS/nixpkgs/issues/545287

- @eveeifyeve: how can we increase adoption
    - @roberth: we could iterate faster out-of-tree
    - @kiaragrouwstra: out-of-tree we could also observe what boilerplate we need to clean up
    - @eveeifyeve: it's important
    - @kiaragrouwstra: not having to worry about breakage would be very helpful
    - @kiaragrouwstra: do we really want more modules
    - @aanderse: I agree with Kiara that we don't want to push for more modules and users because the interface is still almost entirely useless, except for rare use cases. The problem is that the hurdles haven't been addressed yet, and when that's done the floodgates can open
    - @aanderse: If we push before e.g. users is implemented, that would not fly with many NixOS folks
    - @eveeifyeve: what is the consensus about hardening
    - @roberth: great question! this is something we need to figure out
    - @roberth: both the escape hatch and generalization into portable options have a place
    - @aanderse: how do we make security mechanisms work, with something like a decorator pattern? for apparmor, bubblewrap, etc

- @kiaragrouwstra: do we move forward with the new repo?
    - @kiaragrouwstra: do we pin NixOS?
    - @eveeifyeve: we should fork Nixpkgs, worked for cygwin
    - @roberth: if we also fork we can't use our fork with cygwin
    - @kiaragrouwstra: I don't think forking is helpful; can we use nixpkgs as an input
    - @roberth: disabledModules
    - @aanderse: you're taking yourself out of the privileged position of being in the monorepo
    - @roberth: probably ok for now
- Pr Reviews...
    

</details>

# modular services meeting 2026-08-21

<details>
<summary>

Posted: https://discourse.nixos.org/t/modular-services-meeting-7-2026-08-21/79684

</summary>
  
Attendees: @eveeifyeve @roberth @lassulus @aanderse @kiaragrouwstra and 1 other.

- @eveeifyeve: Do we want an allowNetwork option?
    - @lassulus: Quite service manager specific
    - @aanderse: Should be in scope and is worth doing
    - @roberth: In scope, and modular services integrations can bring in other tools if needed
    - @lassulus: I don't think we'd want to run tools like bubblewrap inside systemd, but otherwise writing the interface is a lot of work
    - @aanderse: It's a point people bring up as a point of contention. Figuring out the interface is the task of the modular services project.
    - @roberth: I think we agree on scope and can work out the details. `allowNetwork` seems like a good one to add.

- @eveeifyeve: Which flake attribute?
    - @roberth: I would suggest `<flake>.modules.service.<name>`, matching the module `class`, which we might want to change to `packageConfig` or something
    - @eveeifyeve: Not sure if the distinction is clear enough to users.
    - @lassulus: They're similar but you don't have to run a command as service
    - @lassulus: Package modules name was kind of taken by Nixpkgs architecture team at some point, but did not materialize
    - @kiara: modular programs seems to focused around binaries
    - @lassulus: It's an is-a relationship where all modular services are package modules, but not all package modules are service modules.
    - @roberth: Similar to NixOS services, NixOS programs are global and package modules solve the same problem of making them usable in any context, not just NixOS
    - @eveeifyeve: What about window managers
    - @lassulus: Good example, because e.g. you can invoke a compositor from the Linux terminal
    - @eveeifyeve: What about running e.g. hyprland on say finix using modular services
    - @aanderse: hyprland does just work because it's just a program, and most of those just work
    - @aanderse: before systemd, launching from the terminal was fairly normal practice
    - @eveeifyeve: Could we have a universal repo for all configuration management.
    - @aanderse: even if modular services was highly successful not all configuration would move to that
    - @roberth: forks and reimplementations are good because innovations are possible and they can even transfer back into the popular main thing, e.g. NixOS
    - @eveeifyeve: I've been playing around with implementing a general configuration manager like that
    - @aanderse: cool idea. I've had to port modules to finix that weren't always great and portability at the system level would help a lot.
    - @eveeifyeve: yeah. configurations that are not necessarily locked to NixOS.
    - @roberth: that would be something like "portable system modules"?
    - @eveeifyeve: I was calling it universal
    - @roberth: system indicates the scale it operates at, which is useful


- @kiara: Separate repo?
    - https://github.com/KiaraGrouwstra/modular-services
    - @roberth: Great!
    - Creating an org for it...
    - @kiaragrouwstra: apparently the free org offering is quite limited
    - @roberth: considering a systemd unit logic refactor to make it independently usable. Not sure where to put it now.
    - @lassulus: refactor in `nixpkgs` can be done later
    - @kiaragrouwstra: divergence is ok; otherwise we've just reinvented the same workflow with extra steps
    - @eveeifyeve: we should communicate that we work should be done
    - @kiara: I don't think nixpkgs gets flooded
    - @roberth: we can also see it as a QA step

- @eveeifyeve: I'm planning to run hydra on RPi and chromebook with finix, on a macbook and some more.
    - @aanderse: 🤩

- @kiaragrouwstra: what to work on next
    - @aanderse: research the use of shims and security, to inform how we could design the interface
    - @roberth: I won't be making progress on https://github.com/NixOS/nixpkgs/issues/545287 anytime soon probably
 

- Pr Review 
    - https://github.com/NixOS/nixpkgs/pull/545732
        - @eveeifyeve: ran the normal eval test, couldn't run NixOS Specific test due to https://github.com/NixOS/nixpkgs/pull/551799 
    - https://github.com/NixOS/nixpkgs/pull/551799
        - @eveeifyeve: Remembered running nixos tests on darwin
        - @anderse: Not well versed and confident enough to merge this pr.
    - https://github.com/NixOS/nixpkgs/pull/518717 
        - @eveeifyeve: Does this reload with reloadCommand/reloadSignal or is this a seperate thing?
        - @kiara: Yeah it should
        - @kiara: Mentions the idea of opting out of reloads.
        - @eveeifyeve: Should be opt in? Because ideally we don't have a service that will be reloading configs by default.
        - @aaderse: Concern about it being systemd specific implementation

</details>