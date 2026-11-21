# Roots Classic → Horizon

> **Slice 2 (2026-11-21): version 0.2.1 at pin `0a875da` (Nightly 2026-11-20), mixins
> `e59da909…`.** The powder chain — Growth Powder and Mutating Powder with its three mutations — is
> in; `notes.md` → **`## Slice 2 — the powder chain`** is the current state for that slice. The
> `0b14f8a` block below stays as the migration record (its `[native] horizon` is now `0a875da`).
>
> **Format (2026-11-18): the port is a flat SDK `.hmod` now.** Horizon's mod-API merge (#16941,
> launcher ≥ 0.2.70) retired `.hnmod`; the 0.1.0 bundle this file describes below (PR **#808**,
> closed by the format purge) was migrated to `horizon-mod.toml` + `Cargo.toml` + `src/lib.rs`
> (`impl mod_api::Hooks`) + `src/runtime.rs` + `assets/` + `data/` at Horizon
> **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** / horizon-mixins
> **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, mod API `0.2`, port version **0.2.0**. Read
> **`## Migration to the SDK format`** at the end of this file first: it is the current state.
> Everything above it is the history of the retired bundle (pin `1d63e0a5`, `.hnmod`, `mixins/`,
> `content/`, `tools/horizon.py`, the staging ladder) and is kept as the record, not as
> instructions — none of `compatibility.json`, `rust-toolchain.toml`, `mixins/<id>/`,
> `content/` or `rootsclassic.hnmod` exists any more. The retired tree is preserved under
> `../_shared/evidence/rootsclassic/retired-hnmod-0.1.0/`.

Ported from **Roots Classic 1.21.1-1.5.10**
(`Lothrazar/RootsClassic`, **MIT**), Minecraft Java 1.21.1 NeoForge, read from
`ports/_shared/upstream/rootsclassic` at branch `1.21.1`, commit
`db9aa883b7a54a1558dbc710546be1f42544be72` (the jar's build day). The upstream
source and the jar were read for behaviour and assets only; the Rust is a
clean-room rewrite. The exact ATM10 jar
(`RootsClassic-1.21.1-1.5.10.jar`, SHA-1 `7d02ec46…`) is kept at
[`../_shared/carry-work/rootsclassic/`](../_shared/carry-work/rootsclassic/SOURCE.md).
Local-only until publishing is approved (ARCHITECTURE.md §8).

## Approach (from the pin's `docs/modpacks.md`)

- **Class `content`, tier `deep`** (`ports/ledger.csv` row 409; provenance
  `ports/_shared/source-map/atm10-sources.csv`). The tier is the pack's (the
  mod as a whole has rituals, standing stones, staves, a mob and renderers).
  This job is **slice 1 of the content half**: the *herbs and their first
  uses* — carried-over plant content plus the two behaviour pieces the jar
  needs for that loop (the global forage modifier and the eaten effects). No
  block entity, menu, screen, entity or renderer is built here; those belong to
  the mod's `machines`/`deep` features and are gaps below.
- **Licence:** **MIT**, read from the jar's `META-INF/neoforge.mods.toml`
  (`license="MIT"`) and the repository's `LICENSE.txt` → **rank 0**
  (permissive). `precheck-mod.py rootsclassic` exits 0 and reports MIT; the
  source map's "unknown (read mods.toml at import)" is corrected by the jar.
  Ported now because it is a core `content` mod at rank 0 and the herbs are the
  pack's own early-game foraging loop.
- **Carry-over vs agent port:** the blockstates, block/item models, textures,
  the `#rootsclassic:berries` tag and the jar's lang names are carried
  byte-for-byte (`tools/carry_content.py`); the 26.3 data files (block/item
  declarations, the 4 loot tables, 5 recipes, the `c:crops/wheat` tag, the
  creative tab) are written from the jar's values; the forage table and the
  eaten `heal` are the agent port.

## Slice 1 — the herbs, the forage and their first uses

- Three herb blocks, on the `minecraft:dandelion` template (the jar's `Block`
  is a `BushBlock`): one state, a flower's empty collision, the template's
  survival check against soil, and a carried loot table that drops the herb
  itself. The jar's own 4x8x4 px outline is not declared (see the deviations).
- The jar's **global loot modifier** as `native_loot_drops` (API 75): a broken
  `short_grass` may add `old_root`, a `wheat`/`carrots`/`potatoes`/`beetroots`
  at its last age a `verdant_sprig`, a `nether_wart[age=3]` an `infernal_bulb`,
  a `chorus_flower` a `dragons_eye`, and leaves that dropped no leaf block one
  of the five berries. Each roll is `random.nextInt(chance) == 0` at the
  jar's `1/N` chances, read from `config/rootsclassic-common.toml` (same file,
  section, keys, defaults and `0..=32767` range as `config/RootsConfig`); the
  file is written with the defaults when missing.
- The five berries and the four materials as items with the jar's exact
  `RootsFoods` numbers (26.3 `saturation` = `2 × nutrition × modifier`), the
  NeoForge compostables map as 26.3 compostable providers, and the
  `infernal_bulb`'s 2400-tick burn (26.3 states it as blaze-rod cooking fuel).
- Eaten effects as 26.3 consume effects: `nightshade` → Poison 320 ticks,
  `elderberry` → `clear_all_effects`, `dragons_eye` → `teleport_randomly`
  (diameter 32) with a 1-second cooldown, and `rootsclassic:heal` (a kind of the
  port's own, `native_consume_effect`, API 74) for `redcurrant` (+2) and
  `healing_poultice` (+5, always edible, stack 8) applied through
  `native_set_player_status`.
- Five recipes carried in 26.3 shape: the two mirrored `pestle` variants,
  `rooty_stew`, `fruit_salad`, `healing_poultice` (2 per craft), plus the
  `c:crops/wheat` tag the stew needs (26.3 ships no `c:` tags).
- A `Roots Classic` creative tab with the carried items.

### Deliberate deviations

| Area | Upstream | This slice |
|---|---|---|
| leaf blocks | `Block instanceof LeavesBlock` | id suffix `_leaves` (every vanilla leaf; a modded leaf with another name is not foraged) |
| the shears rule | global condition (`#c:tools/shear`) **and** "no leaf block in the drops" | both, as upstream: `minecraft:shears` in the tool, and the broken leaf block in the drops |
| `rootsclassic:heal` | `LivingEntity.heal(amount)`, which fires the heal event | `native_set_player_status(uuid, health + amount)`; a mod that cancels healing sees no event (no `native_living_heal` write path) |
| dragon's eye | `±16` X/Z, `y + nextInt(32) − 8`, 32 attempts | vanilla `teleport_randomly` diameter 32: `±16` X/Z, symmetric Y, 16 attempts; same clamp, chorus sound, 20-tick cooldown |
| infernal bulb burn | an override of `getBurnTime` = 2400 | `minecraft:cooking_fuel` with `minecraft:cooking/time_blaze_rod` (2400 at the default speed) |
| item tooltips | `appendHoverText` | not drawn (a `native_tooltip` slice) |
| herb outline | `Block.box(6,0,6,10,8,10)` (4x8x4 px) | the template flower's outline: a declared `shapes` override on a plant template gave the block an **empty pick outline** at this pin (the client's ray passed straight through it and `ctl break` answered "no face … is visible"), so the herbs keep the vanilla flower shape; the collision stays empty either way. Worth reporting upstream as a content-shape issue |
| mutation, bark knife, mortar | items and blocks | **not carried** — the three herbs have no survival source in this slice (creative/`/give`); recorded as the next slice |

## Slice 1b — packaging: one file, no separate content download

The registry keeps **one `file` per version** and publishes native mods as `.hnmod`
(`AGENT_PLAYBOOK.md` §1.0), so a split `rootsclassic.hnmod` + `content/rootsclassic.hmod`
pair could not be listed faithfully: a player would get the code without the herbs or the
herbs without the forage. The port now ships the **AE2 embedding** instead
(`AGENTS.md`, `ARCHITECTURE.md` §8 "Embedded content works"):

- `mixins/rootsclassic/data/rootsclassic-content.hmod` is the built
  `content/rootsclassic.hmod` (27,131 B, SHA-256 `a2d85362…4cd67`, 80 entries), carried
  byte for byte. The mixin CLI stages it as `native-data/rootsclassic/`, and
  `horizon_client::native_data!` compiles it into the game.
- `mixins/rootsclassic/embedded_content.rs` is one `content_root` injection
  (`kind = "HEAD"`, `cancellable = true` — a raw target, not a catalogued hook): at start it
  writes the bytes to `.horizon-cache/rootsclassic-embedded-content.hmod` (only when they
  differ from the copy on disk) and calls `content_root` again with that path appended to the
  dev list, so the content is on whenever the native mod is built in. An installed copy of the
  mod still wins, as the first read.
- `tools/package.py` packs `mixins/<id>/data/**` and **refuses** a `data/<id>-content.hmod`
  that is missing or differs from `content/<id>.hmod`; `tools/package.sh` builds the `.hmod`,
  checks it, copies it into `data/`, then packages and runs
  `cargo horizon-mod check rootsclassic.hnmod --kind native-mod`.

The delivered artifact is now **one `rootsclassic.hnmod`** (24,571 B, SHA-256
`b8152664…248e`, 8 entries, including `mixins/rootsclassic/data/rootsclassic-content.hmod`);
`content/rootsclassic.hmod` stays in the port as the build input, not as a second thing a
player installs. No gameplay code changed: the runtime, the two hook helpers and the content
are the same bytes as slice 1, and the full scenario passes with **no `--dev-mod`** (below).

The sizes and hashes quoted in this paragraph are the pre-0.1.0 build; slice 1c
below replaced them (only the manifest version string changed).

A second pass came out of this slice:

- **The e2e arena killed the player.** The End arena stands over the central island, and the
  dragon killed the survival player mid-scenario in the first embedded run ("Player54969 was
  slain by Ender Dragon"). `arena()` now clears the level (`kill @e[type=!player]`, as
  `charginggadgets` does) so the run is deterministic instead of lucky. No assertion changed.
- **`tools/audit` could not audit this bundle.** It asserted `cancellable == false` (the
  `content_root` injection is cancellable), looked up a support module's file only among the
  *injection* files (the hooks live in `game/native_hooks.rs`, the modules in `game.rs`, so
  the check panicked with a `None`), and compared whole files by re-render — impossible
  against a planner that re-renders the file it edits (it wraps a struct-literal match arm in
  a block, adds trailing commas). It now accepts a cancellable HEAD (and compares exactly the
  `ControlFlow::Break` statement it generates), collects every file the plan touches, and
  checks the item list (named items by name, `impl`/`use`/`macro` by count) instead of
  pretending a re-rendered file is byte-identical.

## Slice 1c — the port's own version (0.1.0)

The upstream reviewer's rule (`AGENT_PLAYBOOK.md` §1.7) is that the registry
version is the **port's** version, not the original mod's: `cargo horizon-mod
check` printed `rootsclassic 1.21.1-1.5.10`, which would have made the entry
disagree with a `0.1.0` release. The version string now lives where the packagers
read it:

- `content/horizon-mod.toml` → `version = "0.1.0"` (what `horizon-mod build`
  stamps into the `.hmod`);
- `mixins/rootsclassic/horizon-mixin.toml` `[mod] version = "0.1.0"` (what
  `tools/package.py` writes into `horizon-native.json`, so the `.hnmod` and
  `cargo horizon-mod check` print it);
- `tools/carry_content.py` → `VERSION = "0.1.0"` for the generated manifest, with
  `UPSTREAM_VERSION = "1.21.1-1.5.10"` kept for the provenance comment, so
  `carry_content.py --check` still reports `80 files, 0 pending` and a
  regeneration cannot revert the version;
- the crate's own `Cargo.toml`/`Cargo.lock` → `0.1.0`, like the other ports.

Only the version string changed: no gameplay code, content bytes or data file was
touched. Repackaging gave, twice in a row, byte-identical artifacts:

| Artifact | Size | SHA-256 | Entries |
|---|---|---|---|
| `content/rootsclassic.hmod` (build input) | 27,130 B | `3427d442c83ad3101c93038ab889de3d243bd655e7327c1bfa31456d0d8c4958` | 80 |
| `mixins/rootsclassic/data/rootsclassic-content.hmod` (embedded copy) | 27,130 B | `3427d442…c4958` | 80 |
| `rootsclassic.hnmod` (**the deliverable**) | 24,562 B | `054a2e51b9d4f8f29a18575028be24eb6598c72da23fc6173545c30b307dbcf7` | 8 |

`cargo horizon-mod check` prints `rootsclassic 0.1.0` for both the content mod and
the native bundle, and the embedded e2e leg was re-run unchanged (the cache `cmp`
and `native_data!` both depend on the rebuilt bytes): the same scenario passes,
the selftest still exits 1, and the checker still reads 4/4 logs as ok.

## Slice boundary (what this port is)

**In:** the three herbs as plants; the forage table and its config; the five
berries, the four materials, the three dishes and the pestle as items with the
jar's food/effect numbers; five recipes; the berries tag; the creative tab.

**Out (gaps, next slices):** ~~Mutating Powder and the three mutation recipes~~
(**in since slice 2**, 0.2.1); the Bark Knife and the six barks (needs a held-stack damage helper and
a `use_item_on` hook); the Mortar, Pestle spell crafting and the component
recipes; the Altar and every ritual; the ten standing stones and their block
entities; the Brazier; the Imbuer; Staves, Crystal Staff, Runic Focus/Tablet and
the mana bar; the living tools and the two armour sets; the Phantom Skeleton;
the JEI plugin; the Patchouli-style Runic Tablet guide; the config's
`[magic]`/`[client]` sections; the tooltips; particles and sounds.

## Verification

Pin `1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` / horizon-mixins
`5a64af938ec86b00d53d16a408aabc0038fb3e57` (schema 6). Every step through
`ports/tools/build-slot.sh` with `CARGO_INCREMENTAL=0`. Evidence:
[`../_shared/evidence/rootsclassic/`](../_shared/evidence/rootsclassic/).

| Step | Command | Result |
|---|---|---|
| runtime tests (red) | `cargo test` before the implementation | 56 compile errors (`heal_target`/`classify`/`Chances` missing) |
| runtime tests (standalone) | `cargo test --locked --offline` in the port | **14 passed**, 0 failed (`runtime-green.log`) |
| fmt | `cargo fmt --all -- --check` | `FMT_EXIT=0` (`fmt.log`) |
| helper fmt | `rustfmt --check --edition 2024 mixins/rootsclassic/embedded_content.rs` | `FMT_HELPER_EXIT=0` (`fmt-helper.log`) |
| clippy | `cargo clippy --all-targets --locked --offline -- -D warnings` | `CLIPPY_EXIT=0`, **0 warnings** (`clippy.log`) |
| stage | `python3 tools/horizon.py stage --horizon …/horizon-1d63e0a` | ok, **2 modules, 3 injections** (`horizon-stage.log`) |
| check | `python3 tools/horizon.py check --horizon …` | `cargo_exit: 0`, **0 warnings** (`horizon-check.log`) |
| embedded tests | `python3 tools/horizon.py test --horizon …` (`--lib`) | **14 passed; 0 failed; 1240 filtered out** (`horizon-test.log`) |
| fast build | `python3 tools/horizon.py build --horizon …` | `cargo_exit: 0` (`horizon-build.log`) |
| stage audit | `python3 tools/test_stage.py` | 3 injections, 2 modules, deterministic bytes, checkout unchanged (`test-stage.log`) |
| content carry | `python3 tools/carry_content.py --check` | **80 files, 0 pending**, jar SHA-1 `7d02ec46…` |
| content `.hmod` | `cargo-horizon-mod build` in `content/` | exit 0, **27,130 B**, SHA-256 `3427d442…c4958`, **80 files**, `no code: content only` |
| embedded copy | `cmp content/rootsclassic.hmod mixins/rootsclassic/data/rootsclassic-content.hmod` | identical (`package.log`) |
| native `.hnmod` | `python3 tools/package.py` (twice, byte-identical) | **24,562 B**, SHA-256 `054a2e51…dbcf7`, **8 entries** incl. the content (`package.log`) |
| bundle check | `cargo horizon-mod check rootsclassic.hnmod --kind native-mod` | exit 0, `rootsclassic 0.1.0`, `native-mod, format native-1/1d63e0a…/5a64af93…, for 26.3` (`hnmod-check.log`, `package.log`) |
| content check | `cargo horizon-mod check content/rootsclassic.hmod` | exit 0, `rootsclassic 0.1.0`, `mod, API 0.2, both` (`hmod-check.log`) |
| e2e (embedded) | `build-slot.sh e2e … -- tools/e2e-all.sh` | **`PASS` + `EXIT:0`**, from one `.hnmod` with **no `--dev-mod`**, re-run at 0.1.0 (`e2e-embedded.log`) |
| e2e control | the same run, `.horizon-cache` a plain file | ids unknown, cache untouched — the PASS is not vacuous (`e2e-embedded.log`) |
| e2e (selftest) | `SELFTEST=1 …` | **exit 1** at `FAIL: SELFTEST: shears foraged no berry (the control is alive)` (`e2e-embedded-selftest.log`) |
| e2e log checker | `python3 ports/tools/check-e2e-logs.py rootsclassic --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0`, `CHECKER_EXIT=0` (`check-e2e-logs.log`) |
| upstream gate | `python3 ports/tools/upstream_ready.py rootsclassic` | `READY`, exit 0, artifact `rootsclassic.hnmod` |

The slice-1 logs are kept as `e2e-pre-embedding.log` / `e2e-pre-embedding-selftest.log`
(they were `e2e-default.log`/`e2e-selftest.log` before the embedding); two failed debugging
runs from before slice 1 were still in the evidence directory and are now in
`evidence/rootsclassic/superseded/`.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Review repairs (PR #646)

The reviewer's open item is validation evidence (the registry release/staging
fetch, HTTP 404 before compilation), which is the orchestrator's to answer
(horizon-mods#686). No code or entry defect was reported. The notices the
reviewer asks for in every artifact are packaged (`mixins/rootsclassic/LICENSE`
and `NOTICE.md`, plus the same two files at the embedded content archive's
root), and the artifact was repackaged twice with the same SHA-256.

### Verification after the repairs

- Artifact: `rootsclassic.hnmod`, 27,774 B, SHA-256 `191def4f8002b8eca40a283f7bb3122dcd4a5130fbd1629d0e22754b84adae8f` (rebuilt twice, identical bytes; `tools/package.py`; the embedded content equals `content/rootsclassic.hmod`).
- `python3 ports/tools/upstream_ready.py rootsclassic` and `check-skills.py --notes ports/rootsclassic`: exit 0.

## Migration to the SDK format (2026-11-18, SDK `0b14f8a`)

Horizon's mod-API merge (#16941, launcher ≥ 0.2.70) retired the `.hnmod` container and the
registry closed every `.hnmod` submission on 2026-11-18 with one reason — *"republish this as a
native `.hmod` with the SDK from the next Nightly"*. The retired bundle this file describes was
PR **#808**; the resubmission is **0.2.0** and supersedes it (changelog at the end).

- **Pin:** Horizon **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** (nightly 2026-11-18),
  horizon-mixins **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, mod API **`0.2`**, launcher
  0.2.78, SDK `package_format` **6** (749 surface items; fetched into `.horizon/sdk/`, never
  packed).
- **Version:** the port's own **0.2.0** (the retired bundle was 0.1.0; a resubmission is always a
  new version — `AGENT_PLAYBOOK.md` §1.7).
- **Class + tier unchanged:** class **content**, tier **deep** for the mod as a whole; this slice
  is still tier `logic` — the same pure runtime, the same two behaviours, no machine or deep
  feature added by the migration.

### File map (what the package is now)

| Path | What it holds |
|---|---|
| `horizon-mod.toml` | the only manifest and the only identity: `id = "rootsclassic"`, `version = "0.2.0"`, `api = "0.2"`, `side = "both"`, `capabilities = ["registries"]`, and `[native]` with the exact `game`/`horizon`/`mixins` |
| `Cargo.toml` | one crate, `name = "rootsclassic"`, edition 2024, no `rust-version` (the box's 1.95 must be allowed); its only dependency is `horizon-mod-api` from `.horizon/sdk/` |
| `src/lib.rs` | the one `#[mod_api::horizon_mod] impl Hooks` — `register`, `register_configs`, `config_loading`, `loot_drops`, `consume_effect` — plus the glue (`split_state`, `heal_amount`, `default_config`) and 5 glue tests |
| `src/runtime.rs` | the pure rules, **byte-identical** to the retired `mixins/rootsclassic/runtime.rs`, 14 tests |
| `assets/rootsclassic/` | the carried assets: blockstates, block/item models, textures, lang (53 files) |
| `data/rootsclassic/`, `data/c/` | the 26.3 data: 3 herb block declarations + loot tables, 12 item declarations, 5 recipes, the berries tag, the creative tab, `c:crops/wheat` (26 files) |
| `LICENSE`, `LICENSE-NOTICE.md`, `README.md` | inside the package (the MIT notice condition, and the layout a reader sees) |
| `rootsclassic.hmod` | the delivered package, in the port root |
| `.gitignore` | `/target`, `/.horizon`, `/Cargo.lock` |

Retired and moved to `../_shared/evidence/rootsclassic/retired-hnmod-0.1.0/` **before** the first
build (a leftover path refuses the package with `unexpected package path`):

| Deleted | Why | What carried over |
|---|---|---|
| `mixins/rootsclassic/` (`horizon-mixin.toml`, `support.rs`, `loot_drops.rs`, `consume_effect.rs`, `embedded_content.rs`, `data/rootsclassic-content.hmod`) | the plan/injection schema and per-hook helper files are not part of any SDK package | `runtime.rs` → `src/`; the two hook bodies → `Hooks::loot_drops`/`Hooks::consume_effect` in `src/lib.rs`; the embedding → nothing (see below) |
| `content/` (`horizon-mod.toml`, `assets/`, `data/`, `rootsclassic.hmod`) | a second package; the flat package carries content itself | `assets/` and `data/` at the package root, paths unchanged |
| `rootsclassic.hnmod`, `target/rootsclassic-0.1.0.hnmod` | the retired container | replaced by the flat `.hmod` |
| `compatibility.json` | the pin is `[native]` in `horizon-mod.toml` | — |
| `rust-toolchain.toml` (1.95.0) | "not part of any new package"; the pin and the launcher decide the toolchain | — |
| `tools/horizon.py`, `tools/package.py`, `tools/package.sh`, `tools/test_stage.py`, `tools/add-notices.py`, `tools/audit/`, `tools/__pycache__/` | the staged/mixin build machinery; there is no stage, plan, module check or repackage step any more | `cargo horizon-mod build|check|fits` |
| `Cargo.lock` (the old crate's) | not needed without registry dependencies, and a packed lock changes the artifact (trap 2) | regenerated per run and deleted before the build |

**Kept on purpose:** `tools/e2e.sh` + `tools/e2e-all.sh` (the in-game scenario is still the only
behaviour oracle — a `STATUS` header now says it needs a launcher-built game and that the
embedded-content legs are `EMBEDDED=1`-only history), `tools/carry_content.py` (re-pointed at
`assets/`/`data/`: `--check` reports **79 files, 0 pending**), `tools/craft_check.py` (the recipe
cases the e2e calls), `FINDINGS.md`, `VALIDATION.md` (history), `LICENSE`, `LICENSE-NOTICE.md`.

**The embedded `.hmod` is gone — the migration's biggest simplification.** The retired bundle
wrote its content half to `.horizon-cache/` from a `content_root` injection (the AE2 pattern),
because the registry keeps one file per project and `.hnmod` could not carry content. The flat SDK
package carries `assets/` and `data/` **inside its own `.hmod`**, so the injection, the static
`native_data!` blob, the cache write, its `Continue`-on-failure control leg and the
`content/`-vs-embedded `cmp` are all deleted.

### Manifest field mapping

| Old | New |
|---|---|
| `horizon-mixin.toml` `[mod] id` / `version` / `priority = 100` | `horizon-mod.toml` `id` / `version = "0.2.0"`; priority is `#[listener(priority = …)]` per hook, unused here |
| `content/horizon-mod.toml` (`id`, `name`, `version`, `authors`, `api`, `side`, `capabilities`) | the same fields in the single manifest; the content package's own manifest is deleted |
| `[compatibility] horizon_revision = 1d63e0a5…` | `[native] horizon = "0b14f8a…"`, plus `game = "26.3"` and `mixins = "e59da909…"` (the mixins revision **moved**: `5a64af93` → `e59da909`) |
| `[[module]] id = "runtime"` / `id = "state"` | no plan section: `src/runtime.rs` is an ordinary module (`pub mod runtime;`) and the glue is the hook bodies |
| `[[injection]] hook = …` + `helper = <file>.rs` + `bindings` | one `Hooks` method of the same name, `host` and `event` in place of the bindings |
| `[[injection]] target = horizon_client::game::mods::content_root` (raw, cancellable) | — (content ships in the package) |
| `horizon-native.json` | gone; the manifest is the only one |

`side = "both"` is the **installation**, not the hook's logical side (an integrated server belongs
to the client installation, so single player and a LAN host need `both`).
`capabilities = ["registries"]` is required by the schema and is also true here: the package
declares blocks and items in `data/`.

### Helper → hook table (verbatim mapping)

| Retired | SDK (0.2) | Where |
|---|---|---|
| `native_loot_drops` v1 HEAD (`loot_drops.rs` → `support.rs::on_loot_drops`) | **`Hooks::loot_drops`**, `contract = "collect"`, `out = "drops"`; `event.context: &LootDrops`, `event.drops: &mut Vec<ItemStack>` | `src/lib.rs` |
| `native_consume_effect` v1 HEAD (`consume_effect.rs` → `support.rs::on_consume_effect`) | **`Hooks::consume_effect`**, listen; `event.kind: &str`, `event.data: &Tag` | `src/lib.rs` |
| `Game::native_config_dir()` + `std::fs::read_to_string`/`write` + `OnceLock<Chances>` | **`Hooks::register_configs`** (`Config::new(MOD_ID, ConfigKind::Common, &default).file("rootsclassic-common.toml")`) + **`Hooks::config_loading`** + `Mutex<Option<Chances>>` | `src/lib.rs` |
| `game.pack.assets.registry.state(state)` → name + `age` | `host.block_state_string(state)` → `split_state("minecraft:wheat[age=7]")` | `src/lib.rs` |
| `drops.iter().any(\|s\| s.item.as_ref() == block.name)` (did the block drop itself) | `host.block_item(state.block())` is the block's own item; compare it with `stack.item()` | `src/lib.rs` |
| `game.native_level_random(dimension)` + `random.next_int_bound(n)` | `host.level(context.dimension)` → `level.with_random(host, \|r\| r.next_int_bound(n))` (the level's own stream, stored back, so vanilla's later draws move too) | `src/lib.rs` |
| `game.native_acting_player()` + `game.native_set_player_status(uuid, health, …)` | `host.players().acting_player()` → `host.living(player.entity())` → `living.health(&*host)` / `living.set_health(host, target)` | `src/lib.rs` |
| the effect payload as `serde_json::Value` | `horizon_core::nbt::Tag` compound; `heal_amount` matches `Double`/`Float`/`Int`/`Long`/`Short`/`Byte` | `src/lib.rs` |
| the item ids as `&str` compared by name | `Registrar::item_key(id)` at `register`, `ItemKey` compared afterwards | `src/lib.rs` |
| `rootsclassic:heal` consume effect type (claimed by the hook) | unchanged: the content still declares `{"type": "rootsclassic:heal", "amount": N}`, and an unclaimed kind is handed to `consume_effect` | `data/rootsclassic/horizon/item/*.json` |

`runtime.rs` is untouched: `classify`, `chance`, `rolls`, `berry`, `heal_target`, `Chances` and the
id constants are called exactly as before. Its sha256 is
`df0d753aa84b432168b7180785cefc0fd9c8fa2e029166ed1e22aa1ca57a5eb0` — `cmp` clean against the
retired file, and the copy **inside** the built package hashes the same.

### Build and check (verbatim)

One lease (`BUILD_LOCAL=1 ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic
--step check -- bash tools/sdk-ladder.sh`), `CARGO_INCREMENTAL=0`, no `--target-dir`:

```sh
cd ports/rootsclassic
cargo test                                        # 19 passed (14 runtime + 5 glue)
cargo fmt --check && cargo clippy --all-targets -- -D warnings   # clean, 0 warnings
rm -f Cargo.lock && cargo horizon-mod build        # -> target/horizon-mod/rootsclassic.hmod
cp target/horizon-mod/rootsclassic.hmod ./rootsclassic.hmod
cargo horizon-mod check rootsclassic.hmod
cargo horizon-mod fits rootsclassic.hmod --build nightly
```

```
rootsclassic 0.2.0 (native-mod, format native-1/0b14f8acfd97fa2c750e42795249dcc981178ca4/e59da9094f0c2fdda6c627fe9eff22dec6a906f0, for 26.3)
  44315 bytes, SHA-256 c1c477d174a3d9be758b1c8a2e13879fc5daa86de945f540a03ca6ac9428a81b, unsigned
CHECK_EXIT:0
Roots Classic:
0b14f8a  made for
FITS_EXIT:0
```

`rootsclassic.hmod`: **44,315 B**, SHA-256
`c1c477d174a3d9be758b1c8a2e13879fc5daa86de945f540a03ca6ac9428a81b`, **87 entries** — the four
manifests/notices/readme, 79 carried content files, `src/lib.rs`, `src/runtime.rs`, `uses.json`.
Two consecutive `cargo horizon-mod build` runs gave identical bytes (no `Cargo.lock` in the zip).

The package's own `uses.json` names the five hooks the mod implements —
`hook:register_configs`, `hook:config_loading`, `hook:loot_drops`, `hook:consume_effect` and
`method:Hooks::register` — plus `ItemsRegistrar::item_key`, `Players::acting_player`,
`RandomSource::next_int_bound`, `BlockStatesHost::block_state_string`, `BlockStatesHost::block_item`
and `LevelRef::with_random` (143 surface entries), so the checker read the glue as intended rather
than seeing unused declarations.

### Traps this migration cost

1. **`cargo fmt` formats `src/runtime.rs` too** (it is an ordinary module now, not an injected
   file). It happened to be rustfmt-clean here, and the byte-for-byte rule was checked again
   after the ladder — but a future rustfmt that reformats it must **not** be obeyed: restore the
   retired bytes with `cp` and record the deviation.
2. **A packed `Cargo.lock` changes the artifact** (imfast's trap 5, re-confirmed): `cargo test`
   and `cargo clippy` write one, and `cargo horizon-mod build` then packs it. Delete it in the
   same command as each build; the delivered zip has no `Cargo.lock` entry.
3. **`.horizon/sdk/` can be seeded from a green sibling port.** No fetch was needed: `diff -r`
   against `ports/_shared/sdk/0b14f8a/api-source` is empty and `build` reads the pin, so
   `cp -a ../imfast/.horizon/sdk .horizon/sdk` gave the same SDK the tool would fetch. Do this
   instead of waiting on the network; verify with `cat .horizon/sdk/build`.
4. **`build-slot.sh` does not `cd` into the port** — `--port` is a label. Wrap every command:
   `bash -c 'cd ports/rootsclassic && …'`.
5. **The new hooks are global hooks, not Parts.** `loot_drops` (collect) and `consume_effect`
   (listen) are `impl Hooks` methods; a Part would be wrong for "any block break / any consumable
   of my kind". There is no SDK equivalent of the per-hook `.rs` helper file: `src/lib.rs` and
   `src/runtime.rs` are the whole code surface.
6. **`acting_player` is on the `Players` service**: `host.players().acting_player()`, not
   `host.acting_player()` (that one is `E0599: method not found in &mut dyn ServerHost`).
7. **`Tag::Float(u32)`/`Tag::Double(u64)` are bit patterns** (`f32::from_bits`/`f64::from_bits`),
   and the effect payload is an NBT `Compound`, not JSON: `data.get("amount")`, matched over every
   numeric tag. `Tag::compound([])` needs a type annotation (`E0283`) — build it with one entry in
   a test instead.
8. **The config file name comes for free**: `Config::new(id, ConfigKind::Common, …)` already names
   `config/<id>-common.toml`; `.file(runtime::CONFIG_FILE)` states the jar's name explicitly, and
   `ConfigKind::Common` is "once per process", exactly NeoForge's common config. The game writes
   the default text when the file is missing, so `support.rs`'s `std::fs` writer is gone.
9. **A block's "did it drop itself" has no item-id read in the public surface**
   (`registry_keys::item_id` is `__private`). `host.block_item(state.block())` is the general
   answer: it is `Block.asItem`, the block's own item, which the leaf rule wants.
10. **`Registrar::item_key` is validated after all declarations**: a missing item refuses the mod
    instead of silently doing nothing. The forage items are this package's own `data/`, so they
    are there by the time the keys are checked (the pattern `wstweaks` uses for its own items).
11. **`cargo horizon-mod build` packs the port root's `README.md`** — editing the README changed
    the artifact from 43,743 B (`5c2b5c1e…`) to 44,315 B (`c1c477d1…`). Re-run `check`/`fits`
    and re-quote the hash after any root-file edit; do not assume the hash from an earlier run.
12. **No in-game run at `0b14f8a`**: `cargo horizon-mod build` packs but does not compile against
    the game (that is `horizon-launcher native-build`), and neither the launcher nor a game build
    for this pin exists on this box (the shared binaries are `1d63e0a5` and `41f822b6`). The
    compile evidence is `cargo test` + `cargo clippy` against the pinned SDK API crate — the same
    crate the launcher builds against — plus `check`/`fits`.

### Verification (SDK `0b14f8a`)

Skills: superpowers/using-superpowers,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

| Check | Command | Result |
|---|---|---|
| `runtime.rs` carried | `cmp src/runtime.rs` against the retired file + `sha256sum` | identical, `df0d753a…a5eb0` (`sdk-0b14f8a/runtime-carry.log`) |
| Rules alone | `cargo test runtime::` | **14 passed**; the migration's *first* build (only `pub mod runtime;` + an empty `impl Hooks`) printed the same 14, so the rules were green before any glue existed (`sdk-0b14f8a/runtime-only.log`) |
| Everything | `cargo test` | **19 passed**, 0 failed (14 runtime + 5 glue) (`sdk-0b14f8a/unit.log`) |
| Formatting | `cargo fmt --check` | clean (`sdk-0b14f8a/fmt.log`) |
| Lints | `cargo clippy --all-targets -- -D warnings` | 0 warnings (`sdk-0b14f8a/clippy.log`) |
| Package | `cargo horizon-mod build`, twice | 44,315 B, same sha256 both runs, 87 entries (`sdk-0b14f8a/build.log`, `build-again.log`, `package-entries.log`) |
| `runtime.rs` in the package | `unzip -p rootsclassic.hmod src/runtime.rs \| sha256sum` | `df0d753a…a5eb0`, byte for byte |
| Registry check | `cargo horizon-mod check rootsclassic.hmod` | `rootsclassic 0.2.0 (native-mod, format native-1/0b14f8a/e59da90, for 26.3)`, **EXIT 0** (`sdk-0b14f8a/check.log`) |
| What it uses | `cargo horizon-mod check … --uses` | 143 entries, five hooks (`sdk-0b14f8a/uses.log`, `uses.json`) |
| Fits the pinned build | `cargo horizon-mod fits rootsclassic.hmod --build nightly` | `0b14f8a  made for`, **EXIT 0** (`sdk-0b14f8a/fits.log`) |
| Content still carried | `python3 tools/carry_content.py --check` | **79 files, 0 pending**, jar sha1 `7d02ec46…` (`sdk-0b14f8a/carry-check.log`) |
| Symbols line | `python3 ports/tools/check-skills.py --notes ports/rootsclassic` | `Skills line present`, gate PASS |

### Gaps after the migration

1. **No in-game run at `0b14f8a`** (no launcher, no game build at this pin): the behaviour
   evidence is still the 0.1.0 run (`e2e-embedded.log`: forage chances 1 and 0, the herb
   place/drop/soil legs, the heals and the recipes), which exercised the *same* `runtime.rs` and
   the same two hooks through a different transport. The first slice on a launcher-capable box
   runs `tools/e2e.sh` with `GAME=<launcher-built horizon-client>` and records the transcript.
2. **No log service in the SDK.** The retired bundle's diagnostics and the e2e's log greps lose
   their `[rootsclassic]` lines; the scenario's assertions already read game state (`ctl block`,
   `ctl effects`, `ctl inventory`) rather than logs, except the `content mods not loaded` check,
   which still works.
3. **The item tooltips and the herb outline** are unchanged gaps from slice 1 (a `native_tooltip`
   / content-shape slice), as are everything in "Slice boundary" above.
4. **`config_loading` reload semantics**: `ConfigKind::Common` loads once per process, so a config
   edit needs a restart — exactly NeoForge's common-config behaviour, recorded because the retired
   port read the file lazily per process from the filesystem.

### Changelog for the resubmission (supersedes #808)

> Supersedes #808, closed because Horizon retired `.hnmod` (#17992). Changes: one flat SDK package
> with `api = "0.2"` and `[native]` pinned to `0b14f8a` (`game = "26.3"`, `mixins = "e59da909…"`);
> the two hooks are now `impl mod_api::Hooks` methods — `loot_drops` (collect, the jar's global
> forage modifier) and `consume_effect` (listen, `rootsclassic:heal`) — over typed `ServerHost`
> reads instead of pin-internal `Game` calls; the config is registered through
> `register_configs`/`config_loading` (`config/rootsclassic-common.toml`, the jar's own keys and
> defaults) instead of a hand-written file; the carried content ships **inside** the package
> (`assets/`, `data/`), so the embedded-content bundle, the `.horizon-cache` write and its control
> leg are gone; `runtime.rs` and its 14 tests are unchanged byte for byte (5 new glue tests, 19
> total). Version 0.2.0. Not yet re-run in game at this pin (no launcher/game build): the last
> green in-game run is the 0.1.0 bundle's.

## Slice 2 — the powder chain (0.2.1, pin `0a875da`)

The slice the gap list called *"Mutating Powder and the three mutation recipes (needs an item-entity
scan around a raycast point, which has no stamped helper)"*, and the one that closes *"the three
herbs have no survival-obtainable source in this slice"*. At `0a875da` the blocker is gone: the SDK
publishes `LevelRef::clip`, `LevelRef::entities_in`, `host.item_entity(…) → ItemEntityRef::stack`,
`EntityRef::discard`, `LevelRef::set_block` and `LevelRef::bone_meal`, which is exactly
`MutatingPowderItem.use` and `GrowthPowderItem.useOn`. The mutating powder's own recipe needs
Growth Powder, so the family is the two powders as one chain.

Class **content**, tier **deep** for the mod; this slice is `logic`-shaped (two item behaviours over
reads and block writes, no block entity, menu, entity or renderer).

### What the jar says (read, not copied)

| Upstream (`db9aa88`, branch `1.21.1`) | Behaviour |
|---|---|
| `item/MutatingPowderItem.use` | `RootsUtil.getRayTrace(level, player, 4)` (40 steps of 0.1, first non-air); item entities in `AABB(pos − 2, pos + 3)`; `MutagenManager.getRecipe`; on a match `setBlockAndUpdate(pos, result)`, **discard every item entity in the box**, `onCrafted`; `stack.shrink(1)` unless creative |
| `mutation/MutagenRecipe.matches` | the box's stacks must be **exactly** the recipe's inputs (`ItemStack.isSameItem`, each removed once, nothing left) and the block must be the base flower |
| `MutagenFlareOrchidRecipe` | `blue_orchid` + `blaze_rod` + `lava_bucket`; Nether; Fire Resistance; netherrack on all 8 horizontal neighbours; `igniteForSeconds(20)` |
| `MutagenMidnightBloomRecipe` | `poppy` + `coal_block`; The End; obsidian two below; Slowness; `persistentData[rootsclassic:RMOD_skipTicks] = 200` |
| `MutagenRadiantDaisyRecipe` | `oxeye_daisy` + `glowstone` + `prismarine_crystals`; Overworld; Night Vision; `5000 < dayTime < 7000`; Blindness 1200 |
| `item/GrowthPowderItem.useOn` | dirt → grass block; water with air above → lily pad above; else a `BonemealableBlock` is random-ticked once; the powder is spent only on `anySuccess`; returns `PASS` |
| `recipe/growth_powder.json` | shapeless `c:seeds/wheat` + `short_grass` + `c:dusts/redstone` + `pestle` → 4 |
| `recipe/mutating_powder.json` | shapeless 4 × `growth_powder` + `c:nether_stars` + `c:crops/nether_wart` + `pestle` → 1 |

### The port

- `src/runtime.rs` (appended after slice 1, which stays a byte prefix of the file):
  `ray_steps` (the 0.1 walk), `Mutation` (base, result, ingredients, `ALL` in `MutagenManager.reload`'s
  order), `MutagenScene` + `mutation()` (the exact-multiset match and each recipe's conditions) and
  `growth()`. Seven new tests.
- `src/lib.rs`: `Powder` (an `ItemPart` on `rootsclassic:mutating_powder`) and `GrowthPowder` (on
  `rootsclassic:growth_powder`), plus the glue: `look_vector` from the entity rotation,
  `ray_target`, `mutation_box`, `neighbours`, `effect_ids`, `data_get`-free reads, `set_block` with
  `UPDATE_ALL`, `discard`, and `spend` through `ItemPlace::PlayerHand::extract` (creative gives
  without losing). Four new glue tests (29 in total).
- Content: `growth_powder` and `mutating_powder` items (`minecraft:sugar` / `minecraft:gunpowder`
  templates, the second `stacksTo(1)`), their two recipes in 26.3 shape with **bare** item/tag
  strings (never the 1.21.1 `{"item": …}` object, which 26.3 refuses), and four convention tags
  `c:seeds/wheat`, `c:dusts/redstone`, `c:nether_stars`, `c:crops/nether_wart`. `carry_content.py`
  went 79 → **93 files, 0 pending**.

### Upstream defects fixed

- **Growth powder never paid for a lily pad.** `GrowthPowderItem.applyGrowthHere`'s water branch
  places the lily pad and then falls out of the `else if` to `return false`, so the caller never
  shrinks the powder: one powder grows lily pads forever. The port returns success from that
  branch. **Reachability, measured:** a player click cannot actually land on a water block at this
  pin (vanilla's block pick ignores fluids — `LevelRef::clip` has `ClipFluid::None`, and
  `ctl interact` on water answers "no face … is visible"), so the branch is upstream's dead path.
  The fix is kept (it is what the code means) and proved by the unit rule `growth_powder_knows_
  dirt_and_water`; the e2e cannot reach it and does not claim to. `probe-growth-branches.log` records
  the measurement (`water: powder 3 -> 3, block now minecraft:water`).

### Deviations

| Area | Upstream | This port |
|---|---|---|
| the powder's block write | client prediction too | server only (the SDK refuses authoritative writes on a `ClientHost`) |
| the growth powder's `PASS` | always `PASS` | `SuccessServer` when the powder acted, `PASS` otherwise. A `PASS` lets the click fall through and be re-issued, which ran `use_on` twice and spent **two** powders for one growth (measured: `3 -> 1`); `SuccessServer` ends the click after the one growth. `PASS` when nothing grew keeps the block's own use as upstream leaves it |
| the bonemealable branch | `state.randomTick` once | `LevelRef::bone_meal` — the closest supported API: same refusal on a block that cannot grow, one growth step, and "did something grow" as the success signal. It can advance a crop further than one random tick (measured: wheat age 0 → 2..5) |
| particles | 40 magic particles on use, 100 in a box on success | not drawn (no `native_particles` slice yet) |

### Traps this slice cost

1. **A powder whose template is a block item places a block.** `growth_powder` was declared with
   `template = "minecraft:redstone"`; clicking stone with it *placed a redstone wire* and spent a
   powder (measured: `stone: powder 3 -> 2 / above minecraft:redstone_wire`). The redstone item
   carries the wire block. Both powders now use plain items (`minecraft:sugar`, `minecraft:gunpowder`)
   and `probe-growth-branches.log` reads `stone: powder 3 -> 3 / above minecraft:air`.
2. **`mutating_powder` is `stacksTo(1)`.** `item replace … with rootsclassic:mutating_powder 2` is
   refused, and `ctl command` still answers `ok:true`; the leg then ran with an empty hand and
   reported "the blue orchid stayed". Every mutation leg now holds **one** and asserts `1 -> 0`.
3. **The Nether ring blocks the line of sight.** Every horizontal neighbour of the flower is
   netherrack, so a click from any side hits the ring. The flare legs stand on a block one above the
   ring, and the aim point is *inside* the flower's outline — a ray that only grazes the top face
   passes over the flower and lands on the netherrack behind (`flare aim: … pos [4,120,3]`).
4. **A flower's shape is smaller than its block.** Aiming at the block centre (y+0.8) misses the
   vanilla flower outline and hits the block behind; y+0.3 is inside it.
5. **A day-old wheat is two pixels tall.** `look-at block … up` answers "no face … is visible"; the
   crop leg aims at a point inside the plant (`look-at 10.5 120.06 16.5`) and clicks with `use-item`.
6. **`ctl save` does not write the player's `.dat`.** For a single-player world the owner's file is
   written by `playerdata::save_owner` when the player leaves or the world closes, so the mutation's
   entity tags were unreadable from disk. `/data get entity @s <path>` works in game (the reply is
   the command's chat line) and needs no quit: `Fire` reads `384s` after the flare orchid and
   `NeoForgeData` reads `{"rootsclassic:RMOD_skipTicks": 200}` after the midnight bloom.
7. **The dragon's eye can land the player in the void.** The teleport is ±16 blocks in three axes;
   the old End floor spanned z −8..40 and a landing outside it killed the player, which the *recipe*
   leg then reported as "the dead screen is open". The arena now fills z −20..40 and the leg
   respawns (if dead), re-tps and clears effects.
8. **A stale SDK rlib is reused across pins.** After replacing `.horizon/sdk` from `0b14f8a` with
   `0a875da`, `cargo test` compiled the new `horizon-mod-vocab` against the *old* `horizon-mod-api-
   macros` (mtimes older than the target) and failed with `cannot find attribute raw_text`. `find
   .horizon/sdk/api -name '*.rs' … | xargs touch` forces the rebuild; `clippy` had already "passed"
   against the stale rlibs, so both were re-run after the touch.

### Coverage (every family this slice ships)

| Family | Status | Evidence |
|---|---|---|
| `growth_powder` item, its recipe (4 per craft) and wrong-ingredient control | **tested** | `craft_check.py` "wheat seeds + short grass + redstone + pestle -> 4 growth powder", control "… stick -> nothing" |
| `mutating_powder` item, its recipe and control | **tested** | `craft_check.py` "4 growth powder + nether star + nether wart + pestle -> mutating powder"; control with 3 growth powder stays empty |
| the four convention tags | **tested** | the recipes above only match through `#c:seeds/wheat`, `#c:dusts/redstone`, `#c:nether_stars`, `#c:crops/nether_wart` |
| growth powder: dirt → grass, powder spent | **tested** | e2e "growth powder PASS: dirt -> minecraft:grass_block, powder 3 -> 2" |
| growth powder: non-growable block, nothing spent | **tested** | "stone control PASS: minecraft:stone unchanged, powder stays 2" |
| growth powder: a young crop grows, powder spent | **tested** | "growing crop PASS: wheat age 0 -> 5, one powder spent" |
| growth powder: water → lily pad | **blocked(unreachable-through-a-click)** | the rule is unit-tested; measured unreachable (defect note above) |
| flare orchid mutation (Nether, ring, Fire Resistance) | **tested** | e2e "flare orchid PASS: rootsclassic:flare_orchid, ingredients gone, powder 1 -> 0" |
| its `igniteForSeconds(20)` | **tested** | "flare orchid PASS: the player burns (Fire=384 ticks, /data get entity @s Fire)" |
| its controls: no Fire Resistance, a bystander item | **tested** | "no-resistance control PASS … the powder is still spent", "extra-item control PASS: … all 3 entities still there" |
| midnight bloom mutation (The End, obsidian two below, Slowness) | **tested** | "midnight bloom PASS: rootsclassic:midnight_bloom" |
| its `skipTicks = 200` | **tested** | "NeoForgeData=… {"rootsclassic:RMOD_skipTicks": 200}" |
| radiant daisy mutation (Overworld, noon, Night Vision) | **tested** | "radiant daisy PASS: rootsclassic:radiant_daisy … powder 1 -> 0" |
| its Blindness 1200 | **tested** | "blindness applied" (the effect list carries `blindness`) |
| its control: midnight instead of noon | **tested** | "midnight control PASS: minecraft:oxeye_daisy kept" |
| particles / sounds | **not ported** | no particle or sound helper in this slice (recorded deviation) |

### Red → green

- **Red (rules):** `cargo test` on `runtime.rs` before the rules existed —
  `error[E0425]: cannot find type Scene in this scope` / `cannot find function ray_steps in this
  scope` (`../_shared/evidence/rootsclassic/sdk-0a875da/slice2-red.log`).
- **Green (rules):** 29 passed (14 slice-1 runtime + 7 slice-2 runtime + 8 glue).
- **Red (in game, first cut):** the growth leg failed with
  `FAIL: growth powder on dirt: 3 -> 1, expected one spent` — one click spent two powders. That log
  was superseded by the next run; the measurement is re-quotable from `probe-double-spend.sh`, which
  now reads `click 1: powder 3 -> 2`.
- **Green (in game):** the full scenario passes, all controls hold, `EXIT:0`.

### Verification (SDK `0a875da`)

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

Everything through `ports/tools/build-slot.sh` with `CARGO_INCREMENTAL=0`; logs in
[`../_shared/evidence/rootsclassic/sdk-0a875da/`](../_shared/evidence/rootsclassic/sdk-0a875da/)
and [`../_shared/evidence/rootsclassic-e2e/`](../_shared/evidence/rootsclassic-e2e/).

| Check | Command | Result |
|---|---|---|
| slice 1 unchanged | `head -c <retired size> src/runtime.rs \| cmp - <retired>` | identical prefix; whole file `6bcfe9ba…` (`runtime-carry.log`) |
| rules + glue | `cargo test` | **29 passed**, 0 failed (`unit.log`, `sdk-test.log`) |
| formatting | `cargo fmt --check` | `FMT_EXIT:0` (`fmt.log`) |
| lints | `cargo clippy --all-targets -- -D warnings` | 0 warnings (`clippy.log`) |
| package | `cargo horizon-mod build`, twice | **59,769 B**, SHA-256 `c49f7f02…4d6f`, same bytes both runs (`build.log`, `build-again.log`, `sha256-both.txt`) |
| registry check | `cargo horizon-mod check rootsclassic.hmod` | `rootsclassic 0.2.1 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, **EXIT 0** (`check.log`) |
| fits the pin | `cargo horizon-mod fits rootsclassic.hmod --build 0a875da` | `0a875da  made for`, **EXIT 0** (`sdk-fits.log`) |
| fits another build | `cargo horizon-mod fits rootsclassic.hmod --build 0b14f8a` | `0b14f8a  fits`, **EXIT 0** (`sdk-fits-other.log`) |
| what it uses | `cargo horizon-mod check … --uses` | 276 entries (`uses.log`, `uses.json`) |
| package contents | `unzip -l` | **101 entries**, no `Cargo.lock`, `src/runtime.rs` = the tree's (`package-entries.log`) |
| content still carried | `python3 tools/carry_content.py --check` | **93 files, 0 pending** (`carry-check.log`) |
| package gate | `python3 ports/tools/verify-sdk-package.py rootsclassic` | **1/1** |
| in game | `launcher-game.sh build rootsclassic` + `build-slot.sh run --step e2e -- bash tools/e2e.sh` | **PASS + EXIT:0** (`rootsclassic-e2e/e2e-launcher.log`) |
| control (the same Nightly without the package) | `GAME=$CONTROL_GAME …` | `FAIL: the consume hook did not heal +2 … the native bundle is not running` + **EXIT:1** (`e2e-control.log`) |
| selftest | `SELFTEST=1 …` | `FAIL: SELFTEST: shears foraged no berry (the control is alive)` + **EXIT:1** (`e2e-selftest.log`) |
| log checker | `python3 ports/tools/check-e2e-logs.py rootsclassic-e2e --strict` | `logs=3 ok=3 missing-exit=0 bad-exit=0` |

Deliverable: `rootsclassic.hmod`, **59,769 B**, SHA-256
`c49f7f02fd788408151f5993636d384b83f48ac98f0d3cefa06e168e1ca64d6f`, version **0.2.1**,
format `native-1/0a875da…/e59da90…`, **101 entries**, no packed `Cargo.lock`.

### Gaps after slice 2

The power chain closes the herbs' source; what is left is unchanged from the migration's list — the
Bark Knife and the six barks (needs a `use_item_on` block transform and a held-stack damage helper),
the Mortar/Pestle spell crafting, the Altar and rituals, the ten standing stones, the Brazier, the
Imbuer, staves and mana, the living tools and armour, the Phantom Skeleton, the JEI plugin, the Runic
Tablet guide, the `[magic]`/`[client]` config sections, item tooltips, and particles/sounds. The
water branch of the growth powder is upstream-dead (see above) and cannot be proved in game at this
pin.
