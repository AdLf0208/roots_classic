# Roots Classic — a Horizon port

**Roots Classic** is a Minecraft mod. Port of Roots 1 originally by Elucent (based on latest public MIT version, with permission from EpicSquid). This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [Lothrazar/RootsClassic](https://github.com/Lothrazar/RootsClassic) — licence **MIT**.

| | |
|---|---|
| Upstream mod | Roots Classic ([source](https://github.com/Lothrazar/RootsClassic)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `rootsclassic.hmod` (install it with the Horizon launcher) |
| Licence | **MIT** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

- The three Roots Classic herbs, the jar's herb-forage table, and the food, effects and reci

## Not yet ported

- **No in-game run at `0b14f8a`** (no launcher, no game build at this pin): the behaviour
- **No log service in the SDK.** The retired bundle's diagnostics and the e2e's log greps lose
- **The item tooltips and the herb outline** are unchanged gaps from slice 1 (a `native_tooltip`
- **`config_loading` reload semantics**: `ConfigKind::Common` loads once per process, so a config

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `rootsclassic.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Roots Classic was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **MIT**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/Lothrazar/RootsClassic

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run rootsclassic` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/rootsclassic/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).
