# Validation — Roots Classic

> **Current: 0.2.1, slice 2 (the powder chain), at pin `0a875da` / mixins `e59da909…`.** The ladder,
> its logs and its hashes are in `notes.md` → **`## Slice 2 — the powder chain`** →
> *Verification*, `../_shared/evidence/rootsclassic/sdk-0a875da/` and the three in-game legs in
> `../_shared/evidence/rootsclassic-e2e/`. Everything from "Slice 1" down is the retired bundle's
> history (`.hnmod`, pin `1d63e0a5`), kept as the record.

## Slice 2 ladder (0.2.1, `0a875da`)

Red → green, in order:

1. **Red (rules):** `cargo test` with only slice 2's tests — 11 compile errors, first
   `error[E0425]: cannot find type Scene in this scope` (`sdk-0a875da/slice2-red.log`).
2. **Green (rules):** 29 passed (14 slice-1 runtime + 7 slice-2 runtime + 8 glue).
3. **Red (in game):** the growth leg failed `FAIL: growth powder on dirt: 3 -> 1, expected one
   spent` — one click spent two powders because a `PASS` answer lets the click be re-issued. Fixed
   by answering `SuccessServer` when the powder acted; `probe-double-spend.log` now reads
   `click 1: powder 3 -> 2`.
4. **Green (in game):** `PASS` + `EXIT:0` with every control (`e2e-launcher.log`), the control leg
   `EXIT:1` (`e2e-control.log`) and `SELFTEST=1` `EXIT:1` (`e2e-selftest.log`);
   `check-e2e-logs.py rootsclassic-e2e --strict` → `logs=3 ok=3 missing-exit=0 bad-exit=0`.

| Step | Evidence |
|---|---|
| slice 1 is a byte prefix of `runtime.rs` | `sdk-0a875da/runtime-carry.log` |
| tests | **29 passed**, 0 failed (`unit.log`, `sdk-test.log`) |
| fmt · clippy | `FMT_EXIT:0` · 0 warnings (`fmt.log`, `clippy.log`) |
| two builds, identical | 59,769 B, `c49f7f02…4d6f` (`build.log`, `build-again.log`, `sha256-both.txt`) |
| `check` · `fits 0a875da` · `fits 0b14f8a` | `check.log` · `made for` · `fits` (`sdk-fits*.log`) |
| package contents | 101 entries, no `Cargo.lock` (`package-entries.log`) |
| carry | 93 files, 0 pending (`carry-check.log`) |
| package gate | `verify-sdk-package.py rootsclassic` → 1/1 |

## Slice 1 — the retired bundle's validation

> **Format note (2026-11-18): history.** This is the retired `.hnmod` bundle's ladder at pin
> `1d63e0a5`. The port is now a flat SDK `.hmod`; the current ladder, its logs and its hashes are
> in `notes.md` → `## Migration to the SDK format` and
> `../_shared/evidence/rootsclassic/sdk-0b14f8a/`. Nothing here can be re-run: `tools/horizon.py`,
> `tools/package.py`, `content/` and `mixins/` no longer exist.

Every command ran through `ports/tools/build-slot.sh` with `CARGO_INCREMENTAL=0`.
Pin `1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9`, horizon-mixins
`5a64af938ec86b00d53d16a408aabc0038fb3e57` (schema 6). Logs live in
[`../_shared/evidence/rootsclassic/`](../_shared/evidence/rootsclassic/).

## Red → green

1. **Red:** `cargo test` on `runtime.rs` with only the tests written — 56
   compile errors (`heal_target`, `classify`, `Chances`, … not found), proving
   the tests drive the implementation.
2. **Green:** the implementation written to the tests: **14 passed**, 0 failed.

## Ladder (re-run for the embedded bundle)

| Step | Evidence |
|---|---|
| runtime tests | **14 passed**, 0 failed (`runtime-green.log`) |
| fmt | `FMT_EXIT=0` (`fmt.log`) |
| helper fmt | `FMT_HELPER_EXIT=0` (`fmt-helper.log`) |
| clippy | `CLIPPY_EXIT=0`, 0 warnings (`clippy.log`) |
| carry check | 80 files, 0 pending (`carry-check.log`) |
| stage | 2 modules, **3 injections** (`horizon-stage.log`) |
| check | `cargo_exit: 0`, 0 warnings (`horizon-check.log`) |
| embedded tests | **14 passed**, 1240 filtered (`horizon-test.log`) |
| fast build | `cargo_exit: 0` (`horizon-build.log`) |
| stage audit | 3 injections, 2 modules, deterministic, checkout unchanged (`test-stage.log`) |
| packages | `.hmod` 27,130 B `3427d442…`, embedded copy identical, `.hnmod` 24,562 B `054a2e51…` (`package.log`) |
| bundle check | `cargo horizon-mod check rootsclassic.hnmod --kind native-mod` → exit 0, prints `rootsclassic 0.1.0` (`package.log`, `hnmod-check.log`) |
| e2e embedded | `PASS` + `EXIT:0`, **no `--dev-mod`** (`e2e-embedded.log`) |
| e2e selftest | `FAIL: SELFTEST: shears foraged no berry` + `EXIT:1` (`e2e-embedded-selftest.log`) |
| e2e checker | `logs=4 ok=4`, exit 0 (`check-e2e-logs.log`) |

The slice-1 pair is kept as `e2e-pre-embedding.log` / `e2e-pre-embedding-selftest.log`.
Two failed debugging runs from before slice 1 were still sitting in the evidence
directory (17:08 and 23:54 on 2026-11-09); they are now in `superseded/` so an
audit cannot read them as the port's result.

## Packages

Version **0.1.0** (the port's own version — `AGENT_PLAYBOOK.md` §1.7; the
upstream mod is 1.21.1-1.5.10 and stays in the provenance notes). Repackaged
twice after the version change with byte-identical results.

| Artifact | Size | SHA-256 | Entries |
|---|---|---|---|
| `content/rootsclassic.hmod` (build input) | 27,130 B | `3427d442c83ad3101c93038ab889de3d243bd655e7327c1bfa31456d0d8c4958` | 80 |
| `mixins/rootsclassic/data/rootsclassic-content.hmod` (embedded copy) | 27,130 B | `3427d442c83ad3101c93038ab889de3d243bd655e7327c1bfa31456d0d8c4958` | 80 |
| `rootsclassic.hnmod` (**the deliverable**) | 24,562 B | `054a2e51b9d4f8f29a18575028be24eb6598c72da23fc6173545c30b307dbcf7` | 8 |

The `.hnmod` holds `horizon-native.json`, `mixins/rootsclassic/` (`horizon-mixin.toml`,
`runtime.rs`, `support.rs`, `loot_drops.rs`, `consume_effect.rs`, `embedded_content.rs`)
and `mixins/rootsclassic/data/rootsclassic-content.hmod`. Rebuilding reproduces the same
SHA-256.

## What the e2e proves (from `e2e-embedded.log`)

- **Launch 0 (control, first):** the same binary with `.horizon-cache` a plain file, so the
  bundle cannot write its content out — `give rootsclassic:old_root` fails and
  `rootsclassic:flare_orchid` stays `minecraft:air`; the cache file is untouched. Without
  this leg the PASS would say nothing about *where* the ids came from.
- **Launch 1 (only the `.hnmod`, no `--dev-mod`):** the bundle writes
  `.horizon-cache/rootsclassic-embedded-content.hmod` (27,130 B, identical to
  `content/rootsclassic.hmod`) and the content mod loads (`no content mods not loaded`).
  Then, unchanged from slice 1: 16 carried ids; the three herbs place on dirt, refuse stone
  and drop themselves (`{"drops":{"rootsclassic:flare_orchid":1}}`, …).
- Forage at chance 1: `short_grass` → `old_root`; `wheat[age=7]` → `verdant_sprig`;
  `nether_wart[age=3]` → `infernal_bulb`; `chorus_flower[age=0]` → `dragons_eye`;
  `oak_leaves` → exactly one berry (`redcurrant` in this run).
- Controls: `wheat[age=0]`, `nether_wart[age=0]`, stone, and leaves broken with shears
  (the shears drop the leaf block itself) forage nothing. `SELFTEST=1` flips the shears
  assertion and the run exits 1, so the control is alive.
- Eaten effects: redcurrant `8.0 → 10.0` (+2), healing poultice `6.0 → 11.0` (+5), old root
  changes nothing, elderberry clears `poison`, nightshade applies `poison`, and the dragon's
  eye moves the player (19.46 blocks in this run — vanilla `teleport_randomly` landing on the
  End island, so the distance varies between runs).
- All five recipes craft in a real table (pestle 1, rooty stew 1, fruit salad 1, healing
  poultice 2) with wrong-ingredient controls staying empty.
- **Launch 2:** the same five breaks forage nothing with every chance set to 0 in
  `config/rootsclassic-common.toml` — the table is driven by the jar's config, not a fixed
  chance.

The arena clears the End (`kill @e[type=!player]`) before the survival breaks: the first
embedded run was killed mid-scenario by the dragon, which is a flaky harness, not a port
failure.
