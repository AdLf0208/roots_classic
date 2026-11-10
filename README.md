# Roots Classic — Horizon port

A port of [Roots Classic](https://github.com/Lothrazar/RootsClassic) by Elucent,
Lothrazar and Mrbysco for Horizon. This slice is **the herbs and their first
uses**: the herb-forage loop and the food, effects and recipes built on it.

- Three herb blocks (`flare_orchid`, `midnight_bloom`, `radiant_daisy`) that
  place on soil, refuse stone and drop themselves.
- The jar's herb-forage table: broken short grass may add an old root, a
  last-age wheat/carrots/potatoes/beetroots a verdant sprig, ripe nether wart an
  infernal bulb, a chorus flower a dragon's eye, and leaves that dropped no leaf
  block one of the five berries — at the jar's configurable `1/N` chances in
  `config/rootsclassic-common.toml` (`0` never, `1` always).
- Five berries, four materials and three dishes as food with the jar's nutrition,
  saturation and eaten effects (nightshade poisons, elderberry clears effects,
  the dragon's eye teleports, redcurrant heals 2, the poultice 5), plus the five
  recipes and a creative tab.

The mutation powder, bark knife, mortar, altar/rituals, standing stones, staves,
living gear, phantom skeleton and the guide are planned gaps — see the entry's
"Not yet ported" list.

**One file:** `rootsclassic.hnmod` carries the content (blocks, items, models,
textures, lang, loot, recipes and the berries tag) inside the bundle and writes
it out at start, so installing the bundle alone gives the herbs, the items and
the forage. Nothing is written into the save.

**Original:** [Roots Classic](https://github.com/Lothrazar/RootsClassic)
1.21.1-1.5.10 by Elucent, Lothrazar and Mrbysco, **MIT**. The original copyright
and licence notices are kept in [LICENSE](LICENSE), and
[LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where the licence was read from.

**Horizon:** a port for [Horizon](https://github.com/horizon-rust/horizon),
Minecraft: Java Edition 26.3 rewritten in Rust. The exact Horizon and
horizon-mixins revisions this port builds against are pinned in
`compatibility.json` (currently Horizon `1d63e0a`, horizon-mixins `5a64af93`).

## Install

1. Take `rootsclassic.hnmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-native-mods` folder — the game folder is
   the one holding `options.txt`.
3. Native mods are always on once installed; the first install shows a trust
   notice, and the launcher builds the mod for your game.

To try it without installing, start the game with
`--dev-mod rootsclassic.hnmod`.

## Build

The bundle is built from these sources with the pinned Horizon toolchain:

```sh
cargo test --locked --offline
python3 tools/horizon.py check --horizon <horizon checkout>
python3 tools/horizon.py build --horizon <horizon checkout>
tools/package.sh          # the content .hmod, then the .hnmod that embeds it
cargo horizon-mod check rootsclassic.hnmod --kind native-mod
```

`tools/package.sh` builds `content/rootsclassic.hmod`, copies it into
`mixins/rootsclassic/data/rootsclassic-content.hmod` (the packager refuses a
mismatch), and packages `rootsclassic.hnmod` with deterministic bytes.

## Compatibility

- Horizon `1d63e0a`, horizon-mixins `5a64af93` (schema 6), game 26.3.
- Hooks used: API 75 `loot_drops`, API 74 `consume_effect`, and one
  `content_root` injection for the embedded content.

## Contributing

The "Not yet ported" list in the registry entry is the roadmap; the port's
`notes.md` carries the details and the deliberate deviations. Open an issue with
what you want to pick up.

## Licence

MIT — see [LICENSE](LICENSE). Original copyright (c) 2016 Team Roots; the port's
Rust is a clean-room rewrite. No Mojang file is included.
