# Design

`doc/` is the manual: what modular services *are*, for someone using them.
This directory is the other half -- how the design got where it is, what it has
not settled, and what the people arguing about it have said.

The two are kept apart on purpose. A manual that hedged every option with the
thread it came from would be unreadable, and a design record that only kept the
conclusions would be worthless: the reason a decision holds is the alternative
it beat, and that lives in the discussion.

| directory | what |
| --- | --- |
| [`crowdsource/`](./crowdsource/README.md) | The discussion itself, fetched from where it happened: nixpkgs issues and pull requests, RFCs, Discourse topics, the Matrix room, the meeting pad and the project board. Refreshed by `nix run .#crowdsource-sync`. Everything under `raw/`, `state/` and `INDEX.md` is generated and should never be hand-edited; `sources.json` is the opposite, and is where the judgement lives. |

Analysis belongs here beside `crowdsource/`, citing files inside it. Anything
that ends up being true of the subsystem as shipped belongs in the manual
instead.
