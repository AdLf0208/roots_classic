# Roots Classic for Horizon — slice 2 (the powder chain)

A clean-room Rust port of **Roots Classic 1.21.1-1.5.10**
(`Lothrazar/RootsClassic`, MIT) for Horizon at **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`**
(nightly 2026-11-20) with horizon-mixins `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API
`0.2`.

This first slice is **the herbs and their first uses**: the three herbs
(`flare_orchid`, `midnight_bloom`, `radiant_daisy`) as placeable plants, the
forage table that hides `old_root` in short grass, `verdant_sprig` in a grown
crop, `infernal_bulb` in ripe nether wart, `dragons_eye` in a chorus flower and
one of the five berries in leaves — at the jar's own configurable `1/N`
chances — plus the five berries and the materials as food with the jar's exact
nutrition, saturation and eaten effects, and the recipes that use them (rooty
stew, fruit salad, healing poultice, the pestle).

Slice 2 makes the herbs survival-obtainable: **Growth Powder** (dirt becomes
grass, a young crop grows, one powder per change) and **Mutating Powder**, the
jar's three mutations — a blue orchid in the Nether, ringed by netherrack and
under Fire Resistance, becomes a flare orchid (and the player burns); a poppy in
The End, above obsidian and under Slowness, becomes a midnight bloom (and the
player's `skipTicks` is set to 200); an oxeye daisy in the Overworld at noon,
under Night Vision, becomes a radiant daisy (and the player is blinded). Both
powders are crafted from the jar's own recipes.

The bark knife, the mortar, the altar and the whole ritual/standing-stone/spell
half are planned gaps (`notes.md`).

## The package

One flat `.hmod` — the SDK format the mod-API merge (#16941) introduced, which retired the
`.hnmod` container:

```text
rootsclassic.hmod
  horizon-mod.toml   the only manifest (id, name, version 0.2.1, api 0.2, side, capabilities, [native])
  Cargo.toml         one crate whose only dependency is the pinned SDK's horizon-mod-api
  src/lib.rs         the one #[mod_api::horizon_mod] impl Hooks: register, register_configs,
                     config_loading, loot_drops, consume_effect, plus the two powder ItemParts
                     and their 8 glue tests
  src/runtime.rs     the pure rules and their 21 tests (slice 1's are a byte prefix of the file,
                     slice 2's are appended)
  assets/, data/     the carried content: textures, models, blockstates, lang, the herbs and items
                     (26.3 declarations), loot tables, recipes, the berries tag, the wheat tag
  LICENSE, LICENSE-NOTICE.md, README.md, uses.json
```

There is no `content/` second package and no `mixins/` tree any more: the content half travels
inside the same file as the code, so one install gives the herbs, the items and the forage. The
retired 0.1.0 tree is kept as evidence under
`ports/_shared/evidence/rootsclassic/retired-hnmod-0.1.0/`.

Local-only until publishing is approved (ARCHITECTURE.md §8); licence MIT, rank 0, see
`LICENSE-NOTICE.md`.

## Run it

```sh
# the pure rules and the glue's conversions, on the host target
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step test \
    -- bash -c 'cd ports/rootsclassic && CARGO_INCREMENTAL=0 cargo test'

# lints (of this crate only: `cargo fmt --check`, never `--all` — the SDK is a path dependency)
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step lint \
    -- bash -c 'cd ports/rootsclassic && cargo fmt --check && cargo clippy --all-targets -- -D warnings'

# the package and the registry's own checks
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step build \
    -- bash -c 'cd ports/rootsclassic && rm -f Cargo.lock && cargo horizon-mod build'
ports/tools/build-slot.sh run --job sdk-rc --port ports/rootsclassic --step check \
    -- bash -c 'cd ports/rootsclassic && cargo horizon-mod check rootsclassic.hmod &&
        cargo horizon-mod fits rootsclassic.hmod --build nightly'
```

`cargo horizon-mod build` packs; it does not compile against the game (that is
`horizon-launcher native-build . --instance <i> --trust-native-code`). `tools/carry_content.py
--check` re-derives the whole carried content from the ATM10 jar and compares it with `assets/`
and `data/` (93 files, 0 pending).

The config the forage table reads is `config/rootsclassic-common.toml` in the game folder (the
jar's own file and key names, written with the jar's defaults when missing). `1` means "always",
`0` means "never" — the e2e uses both as its differential.
