# Roots Classic — upstream findings (slice 1)

Everything below was read from the **exact ATM10 jar** and, for behaviour, from
the upstream repository's `1.21.1` branch, whose head is the jar's build day.
No Java was decompiled and no code was copied; the port is a clean-room Rust
rewrite against the pin's stamped hooks.

## Provenance

| | |
|---|---|
| Mod | Roots Classic 1.21.1-1.5.10 (`RootsClassic-1.21.1-1.5.10.jar`) |
| Jar SHA-1 | `7d02ec46e4d276ebf556cdd529a75108b4724efd` (kept at `ports/_shared/carry-work/rootsclassic/`) |
| Jar SHA-256 | `29d8a909126a93947197ab4b7b8c0bfa779b0f0eeeb0068423254ffb9631c7dc` |
| Jar size | 649,579 B; `Implementation-Timestamp: 2026-09-11T23:31:15+0200` |
| Licence | **MIT**, from the jar's `META-INF/neoforge.mods.toml` (`license="MIT"`) and the repository's `LICENSE.txt` ("The MIT License (MIT) / Copyright (c) 2016 Team Roots") → **rank 0**, local-only until the maintainer approves publishing |
| Upstream | <https://github.com/Lothrazar/RootsClassic>, branch `1.21.1`, commit `db9aa883b7a54a1558dbc710546be1f42544be72` (2026-09-11, "Increment version"); `gradle.properties` says `mod_version=1.5.10`, the jar's version |

Source-map row: `ports/_shared/source-map/atm10-sources.csv` line 409
(`rootsclassic,Roots Classic,content,deep,"unknown (read mods.toml at import)"
,…`). The jar wins over the map: the map's "unknown" is corrected here to MIT,
and `python3 ports/tools/precheck-mod.py rootsclassic` agrees (exit 0, MIT,
rank 0).

## What the jar actually contains (ids, from the jar inventory)

**Blocks (17)** — `assets/rootsclassic/blockstates/` and
`data/rootsclassic/loot_table/blocks/`: `altar`, `brazier`, `imbuer`, `mortar`,
the ten standing stones (`mundane`, `attuned`, `aesthetic`, `accelerator`,
`entangler`, `grower`, `healer`, `igniter`, `repulsor`, `vacuum`) and three
**herbs**: `flare_orchid`, `midnight_bloom`, `radiant_daisy`.

**Items (jar `models/item/`)** — `bark_knife`, `pestle`, `mortar`, `altar`,
`brazier`, `imbuer`, the ten standing stones, `runic_tablet`, `runic_focus`,
`charged_runic_focus`, `spell_powder`, `staff`, `crystal_staff`,
`growth_powder`, `mutating_powder`, `healing_poultice`, `rooty_stew`,
`fruit_salad`, `old_root`, `verdant_sprig`, `infernal_bulb`, `dragons_eye`,
five berries (`blackcurrant`, `redcurrant`, `whitecurrant`, `elderberry`,
`nightshade`), six barks (`oak`, `spruce`, `birch`, `jungle`, `acacia`,
`dark_oak`), five living tools, eight armour pieces and `mana_research_icon`.

**Data** — 18 block loot tables, one entity loot table (`phantom_skeleton`),
43 recipes (crafting, ritual, component), 21 advancement files, seven tags
(`barks/*`, `berries`, two tool tags), four damage types, and one global loot
modifier (`rootsclassic:rootsclassic_drops`).

**No worldgen data** in the jar: the three herbs never generate in the world;
they are made with Mutating Powder (see below).

## Behaviour read from upstream (the parts this slice needs)

### The forage table — `lootmodifiers/DropModifier.BlockDropModifier`

A global loot modifier (`data/rootsclassic/loot_modifiers/rootsclassic_drops.json`,
`data/neoforge/loot_modifiers/global_loot_modifiers.json`) with the single
condition "the tool is **not** in `#c:tools/shear`". On every block break it
may add one stack:

| Broken block | Condition | Drop | Config key, default (1/N) |
|---|---|---|---|
| `minecraft:short_grass` (`TallGrassBlock`) | — | `old_root` | `oldRootDropChance` 40 |
| `wheat`/`carrots`/`potatoes`/`beetroots` | `CropBlock.isMaxAge(state)` | `verdant_sprig` | `verdantSprigDropChance` 30 |
| `minecraft:nether_wart` | `age == 3` | `infernal_bulb` | `infernalStemDropChance` 20 |
| `minecraft:chorus_flower` | — | `dragons_eye` | `dragonsEyeDropChance` 10 |
| any `LeavesBlock` | the rolled loot holds **no** block item of that block (i.e. no shears/silk touch) | one random entry of `#rootsclassic:berries` (five berries) | `berriesDropChance` 25 |

Each roll is `chance > 0 && random.nextInt(chance) == 0` — `1` means always,
`0` means never.

### The herbs themselves — `block/flowers/{FlareOrchid,MidnightBloom,RadiantDaisy}Block`

All three are plain `BushBlock`s: map colour `PLANT`, `noCollission`,
`instabreak`, `pushReaction DESTROY`, one state (`""`), and the same outline
`Block.box(6, 0, 6, 10, 8, 10)` (4×8×4 pixels). Nothing else — no light, no
tick, no effect on contact. Each drops itself (`survives_explosion`).

They are **made, not found**. `item/MutatingPowderItem.use` ray-traces 4 blocks,
matches item entities inside a 5×5×5 box around the target, and the three
`MutagenRecipe`s turn a vanilla flower in place:

| Result | Base block | Ingredients (item entities) | Extra condition | On success |
|---|---|---|---|---|
| `flare_orchid` | blue orchid | blaze rod, lava bucket | Nether, the player has Fire Resistance, netherrack on all 8 neighbours | the player burns 20 s |
| `midnight_bloom` | poppy | coal block | The End, obsidian 2 blocks below, the player has Slowness | the player's `skipTicks` NBT is set to 200 |
| `radiant_daisy` | oxeye daisy | glowstone, prismarine crystals | Overworld, the player has Night Vision, day time 5000–7000 | Blindness 1200 |

The powder shrinks by one (not in creative) whatever happens.

### Food and eaten effects — `registry/RootsFoods`, `item/RootsFoodItem`, `item/DragonsEyeItem`

`saturationModifier` is Java's modifier; the 26.3 `minecraft:food.saturation`
is `2 × nutrition × modifier`, which is how the table below is written.

| Item | Nutrition | Saturation | Extra |
|---|---|---|---|
| `old_root` | 1 | 0.2 | — |
| `dragons_eye` | 2 | 0.4 | random teleport `±16` blocks X/Z, `y + nextInt(32) − 8` clamped, 32 attempts, chorus-fruit sound, 20-tick cooldown |
| `nightshade` | 2 | 0.4 | Poison 320 ticks, probability 1.0 |
| `blackcurrant`, `redcurrant`, `whitecurrant` | 4 | 3.2 | `redcurrant` heals **2** on finish |
| `elderberry` | 2 | 0.4 | `removeAllEffects()` on finish |
| `healing_poultice` | 0 | 0.0 | always edible, heals **5** on finish |
| `rooty_stew` | 7 | 14.0 | — |
| `fruit_salad` | 8 | 14.4 | — |

`infernal_bulb` is not food: it is a 2400-tick furnace fuel.

### Recipes carried in this slice (jar values, 1.21.1 → 26.3 spelling)

| Recipe | Shape / ingredients | Result |
|---|---|---|
| `pestle` (two mirror variants, group `pestle`) | diorite | pestle |
| `rooty_stew` | `#c:crops/wheat` + bowl + `old_root` (shapeless) | rooty_stew |
| `fruit_salad` | 3 melon + apple + bowl + elderberry + whitecurrant + blackcurrant + redcurrant | fruit_salad |
| `healing_poultice` | redcurrant + paper + pestle + verdant_sprig | 2 × healing_poultice |

`#c:crops/wheat` is a NeoForge convention tag the prepared 26.3 resources do
not ship, so the port writes it by hand (`minecraft:wheat`), as
`ports/_shared/carry-pipeline.md` §4.6 says to.

### Config — `config/RootsConfig`, `rootsclassic.toml`

`[items]` carries the five chances above plus `barkKnifeBlockStripChance`
(0.3); `[magic]` carries the spell numbers. This slice reads `[items]` only and
keeps the same names, defaults and ranges; a missing file is written with the
defaults, as NeoForge generates it.

## What the pin can express (slice 1 build)

| Upstream behaviour | Pin mechanism | Verdict |
|---|---|---|
| Global loot modifier on block breaks | `native_loot_drops` (API 75, `collect`) — it hears blocks a player breaks and hands the tool | **in** |
| The three herbs as placeable plants | content blocks on the `minecraft:dandelion` template (a `FlowerBlock`/`BushBlock`), declared 4×8×4 outline and empty collision, carried loot tables | **in** |
| Eaten `heal`, `clear all effects`, `apply poison` | `minecraft:consumable.on_consume_effects`: `minecraft:apply_effects` and `minecraft:clear_all_effects` are data; `heal` is a kind of our own (`rootsclassic:heal`) that `native_consume_effect` (API 74) catches | **in** |
| Dragon's-eye teleport | `minecraft:teleport_randomly` (diameter 32) + `minecraft:use_cooldown`, data only | **in**, with the deviations below |
| Food values / stack sizes | item component patch (`minecraft:food`, `minecraft:max_stack_size`, …) | **in** |
| Mutating Powder mutation | needs a 4-block raycast, an item-entity scan in a 5×5×5 box, a dimension/effect/neighbour test, removing the item entities and igniting/blinding the player. `native_use_item` (API 13) exists and `native_raycast`/`native_view_hit` helpers exist, but there is **no stamped helper to list or discard item entities near a point** (`native_item_entities`, API 42, is a read-only hook, not a helper) | **out — slice 2** |
| Bark Knife on logs | `native_use_item_on` + damage the held stack + `native_set_block`; needs a held-stack damage helper the pin does not stamp | **out — slice 2** |
| Mortar/pestle spell crafting, altar rituals, standing stones, staves, mana, armour, Phantom Skeleton | block entities, menus, screens, entities, renderers, projectiles | **out — later slices** |

## Deliberate deviations recorded for slice 1

- **The herbs use their template's flower outline, not the jar's 4×8×4 box.**
  A declared `shapes` override on a plant template left the block with an
  *empty* pick outline at this pin: the client's ray passed straight through
  the plant (`ctl looking-at` reported the dirt below) and `ctl break`
  answered `no face of block … is visible from here`, while a vanilla
  dandelion placed the same way broke and dropped itself. The herbs
  therefore keep the `minecraft:dandelion` outline; collision is empty in
  both cases. This is a content-shape issue worth an upstream report.
- **Leaves are recognised by id suffix `_leaves`** (upstream: `instanceof
  LeavesBlock`). Every vanilla leaf block ends in `_leaves`; a modded leaf block
  with another name is not foraged. Recorded rather than guessed.
- **The "no shears" rule is applied twice**, as upstream applies it: the tool
  must not be `minecraft:shears`, and the rolled drops must not already hold
  the broken leaf block (shears, silk touch).
- **`rootsclassic:heal` runs on the server thread through
  `native_set_player_status`**: the player's health plus `amount`, capped by
  the game. Upstream calls `LivingEntity.heal`, which also fires the heal
  event; the pin's helper sets the value directly, so a mod that cancels
  healing sees no event. Recorded as a gap.
- **The dragon's eye's vertical spread is symmetric** (vanilla
  `teleport_randomly`, diameter 32) instead of upstream's `+ nextInt(32) − 8`,
  and vanilla tries 16 candidates instead of 32. The X/Z spread, the clamp, the
  chorus-fruit sound, the 20-tick cooldown and "one item per use" are exact.
- **The mutation, the bark knife and the mortar are not carried**, so the three
  herbs have no survival-obtainable source in this slice (creative/`/give`
  only). That is deliberate: carrying half of a mechanic is worse than
  recording it.
- Item tooltips (`rootsclassic.healingitem.tooltip`, …) are `appendHoverText`
  in Java; the pin's `native_tooltip` (API 12) could add them. Left for slice 2
  so the slice stays data + two hooks.
