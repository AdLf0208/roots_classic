#!/usr/bin/env python3
"""Carry the herbs-and-forage slice of Roots Classic 1.21.1-1.5.10 into the package root.

Since the SDK format (2026-11-18) the package is one flat `.hmod`: the carried content
lives at `assets/` and `data/` beside `src/` and the single `horizon-mod.toml`, not in a
second `content/` package.

The jar is the ATM10 one, kept at
`ports/_shared/carry-work/rootsclassic/RootsClassic-1.21.1-1.5.10.jar` (SHA-1
pinned below). Asset bytes are copied verbatim; the data files 26.3 spells
differently (item definitions, loot tables, recipes, tags) are written from the
jar's own values, and the block/item declarations name vanilla templates.

Run: python3 tools/carry_content.py [--jar PATH] [--check]
  --check  compare the files on disk with what the carry would write, exit 1
           on a difference (no writes).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JAR = (
    ROOT.parent / "_shared/carry-work/rootsclassic" / "RootsClassic-1.21.1-1.5.10.jar"
)
JAR_SHA1 = "7d02ec46e4d276ebf556cdd529a75108b4724efd"
MOD = "rootsclassic"
# The version the registry entry and the artifacts carry is the port's own
# (`AGENT_PLAYBOOK.md` §1.7), not the upstream mod's, and it lives in `horizon-mod.toml`
# now (the only manifest); the jar's number stays in the provenance comments and the notes.
UPSTREAM_VERSION = "1.21.1-1.5.10"

HERBS = ["flare_orchid", "midnight_bloom", "radiant_daisy"]
BERRIES = ["blackcurrant", "redcurrant", "whitecurrant", "elderberry", "nightshade"]
MATERIALS = ["old_root", "verdant_sprig", "infernal_bulb", "dragons_eye"]
FOODS = ["rooty_stew", "fruit_salad", "healing_poultice"]
TOOLS = ["pestle"]
ITEMS = BERRIES + MATERIALS + FOODS + TOOLS

# Bytes copied unchanged from the jar (the mod's own MIT assets).
VERBATIM = (
    [f"assets/{MOD}/blockstates/{name}.json" for name in HERBS]
    + [f"assets/{MOD}/models/block/{name}.json" for name in HERBS]
    + [f"assets/{MOD}/models/item/{name}.json" for name in HERBS + ITEMS]
    + [f"assets/{MOD}/textures/block/{name}.png" for name in HERBS]
    + [f"assets/{MOD}/textures/item/{name}.png" for name in ITEMS]
    # The jar's own item tag, needed by the leaf roll (a random entry of it).
    + [f"data/{MOD}/tags/item/berries.json"]
)

# Every carried item copies a vanilla item's components; the table below is
# what RootFoods/RootsRegistry/the items' classes give it.
TEMPLATES = {
    "blackcurrant": "minecraft:sweet_berries",
    "redcurrant": "minecraft:sweet_berries",
    "whitecurrant": "minecraft:sweet_berries",
    "elderberry": "minecraft:sweet_berries",
    "nightshade": "minecraft:sweet_berries",
    "old_root": "minecraft:sweet_berries",
    "verdant_sprig": "minecraft:iron_nugget",
    "infernal_bulb": "minecraft:stick",
    "dragons_eye": "minecraft:chorus_fruit",
    "rooty_stew": "minecraft:mushroom_stew",
    "fruit_salad": "minecraft:mushroom_stew",
    "healing_poultice": "minecraft:sweet_berries",
    "pestle": "minecraft:iron_nugget",
}

# `minecraft:food` is `{nutrition, saturation}` where saturation is 2 x
# nutrition x Java's saturationModifier (apple: 4, 0.3 -> 2.4).
FOOD = {
    "blueberry": (4, 3.2),
    "old_root": (1, 0.2),
    "dragons_eye": (2, 0.4),
    "nightshade": (2, 0.4),
    "elderberry": (2, 0.4),
    "rooty_stew": (7, 14.0),
    "fruit_salad": (8, 14.4),
}
for _berry in ["blackcurrant", "redcurrant", "whitecurrant"]:
    FOOD[_berry] = (4, 3.2)

# The NeoForge compostables data map the jar ships, as 26.3 compostable
# providers (low 0.3, medium 0.65).
COMPOST = {
    "blackcurrant": "minecraft:compostable/low",
    "redcurrant": "minecraft:compostable/low",
    "whitecurrant": "minecraft:compostable/low",
    "elderberry": "minecraft:compostable/medium",
    "nightshade": "minecraft:compostable/medium",
}

HEAL = {"type": f"{MOD}:heal"}


def components(item: str) -> dict:
    """The item's component patch over its template."""
    out: dict = {}
    if item in FOOD:
        out["minecraft:food"] = {
            "nutrition": FOOD[item][0],
            "saturation": FOOD[item][1],
        }
    if item in COMPOST:
        out["minecraft:compostable"] = {"layers": COMPOST[item]}
    elif item in TEMPLATES and TEMPLATES[item] == "minecraft:sweet_berries":
        # The jar's compostables map does not list these; sweet berries compost.
        out["!minecraft:compostable"] = {}
    match item:
        case "redcurrant":
            out["minecraft:consumable"] = {
                "on_consume_effects": [HEAL | {"amount": 2.0}]
            }
        case "healing_poultice":
            out["minecraft:food"] = {
                "nutrition": 0,
                "saturation": 0.0,
                "can_always_eat": True,
            }
            out["minecraft:consumable"] = {
                "on_consume_effects": [HEAL | {"amount": 5.0}]
            }
        case "elderberry":
            out["minecraft:consumable"] = {
                "on_consume_effects": [{"type": "minecraft:clear_all_effects"}]
            }
        case "nightshade":
            out["minecraft:consumable"] = {
                "on_consume_effects": [
                    {
                        "type": "minecraft:apply_effects",
                        "probability": 1.0,
                        "effects": [
                            {
                                "id": "minecraft:poison",
                                "duration": 320,
                                "show_icon": True,
                                "show_particles": True,
                            }
                        ],
                    }
                ]
            }
        case "dragons_eye":
            # DragonsEyeItem: +/-16 blocks X/Z, one chorus-fruit teleport, a
            # one-second cooldown. 26.3 states it as a consume effect.
            out["minecraft:food"] = {"nutrition": 2, "saturation": 0.4}
            out["minecraft:consumable"] = {
                "on_consume_effects": [
                    {"type": "minecraft:teleport_randomly", "diameter": 32.0}
                ]
            }
            out["minecraft:use_cooldown"] = {"seconds": 1.0}
        case "infernal_bulb":
            # InfernalBulbItem.getBurnTime = 2400: blaze-rod time in 26.3.
            out["minecraft:cooking_fuel"] = {
                "burn_time": "minecraft:cooking/time_blaze_rod",
                "speed_multiplier": "minecraft:cooking/speed_default",
            }
        case "rooty_stew" | "fruit_salad":
            # The jar's item is stacksTo(1) with no bowl left behind. (The
            # template's bowl is what a *vanilla* stew leaves.)
            out["!minecraft:use_remainder"] = {}
        case "verdant_sprig":
            pass
    return out


# An item file names `max_stack_size` beside `template` (26.3 refuses it inside
# `components`, which is for block files).
STACK_SIZE = {"healing_poultice": 8, "pestle": 1}


def item_decl(item: str) -> dict:
    decl = {"template": TEMPLATES[item]}
    if item in STACK_SIZE:
        decl["max_stack_size"] = STACK_SIZE[item]
    if components(item):
        decl["components"] = components(item)
    return decl


ITEM_DECLS = {item: item_decl(item) for item in ITEMS}

# Herbs are plain BushBlocks: one state on a vanilla flower template, which
# already has a flower's shape and no collision. A declared `shapes` override on
# a plant template left the block with an *empty* pick outline at this pin (the
# client's ray went straight through it and `ctl break` answered "no face …
# visible"), so the jar's 4x8x4 box is not declared; the template's flower
# outline stands in. Recorded in ../notes.md.
HERB_BLOCK = {"template": "minecraft:dandelion"}

RECIPES = {
    "pestle": {
        "type": "minecraft:crafting_shaped",
        "category": "equipment",
        "group": "pestle",
        "key": {"X": "minecraft:diorite"},
        "pattern": ["  X", "XX ", "XX "],
        "result": {"count": 1, "id": f"{MOD}:pestle"},
    },
    "pestle2": {
        "type": "minecraft:crafting_shaped",
        "category": "equipment",
        "group": "pestle",
        "key": {"X": "minecraft:diorite"},
        "pattern": ["X  ", " XX", " XX"],
        "result": {"count": 1, "id": f"{MOD}:pestle"},
    },
    "rooty_stew": {
        "type": "minecraft:crafting_shapeless",
        "category": "food",
        "ingredients": ["#c:crops/wheat", "minecraft:bowl", f"{MOD}:old_root"],
        "result": {"count": 1, "id": f"{MOD}:rooty_stew"},
    },
    "fruit_salad": {
        "type": "minecraft:crafting_shapeless",
        "category": "food",
        "ingredients": [
            "minecraft:melon",
            "minecraft:melon",
            "minecraft:melon",
            "minecraft:apple",
            "minecraft:bowl",
            f"{MOD}:elderberry",
            f"{MOD}:whitecurrant",
            f"{MOD}:blackcurrant",
            f"{MOD}:redcurrant",
        ],
        "result": {"count": 1, "id": f"{MOD}:fruit_salad"},
    },
    "healing_poultice": {
        "type": "minecraft:crafting_shapeless",
        "category": "food",
        "ingredients": [
            f"{MOD}:redcurrant",
            "minecraft:paper",
            f"{MOD}:pestle",
            f"{MOD}:verdant_sprig",
        ],
        "result": {"count": 2, "id": f"{MOD}:healing_poultice"},
    },
}

# `#c:crops/wheat` is a NeoForge convention tag 26.3 does not ship; the port
# writes it for the mod's own recipe (carry-pipeline.md 4.6).
TAGS = {
    "data/c/tags/item/crops/wheat.json": {"values": ["minecraft:wheat"]},
}

LANG_KEYS = (
    ["itemGroup.rootsclassic"]
    + [f"block.{MOD}.{name}" for name in HERBS]
    + [f"item.{MOD}.{name}" for name in ITEMS]
)

def herb_loot(name: str) -> dict:
    return {
        "type": "minecraft:block",
        "random_sequence": f"{MOD}:blocks/{name}",
        "pools": [
            {
                "bonus_rolls": 0.0,
                "rolls": 1.0,
                # 26.3: one typed condition per pool, not a list of wrappers.
                "condition": {"type": "minecraft:survives_explosion"},
                "entries": [{"type": "minecraft:item", "name": f"{MOD}:{name}"}],
            }
        ],
    }


def generated(lang: dict[str, str]) -> dict[str, bytes]:
    """Every file the carry writes beyond the jar's verbatim bytes."""
    files: dict[str, bytes] = {}
    for name in HERBS:
        files[f"data/{MOD}/horizon/block/{name}.json"] = _json(HERB_BLOCK)
        files[f"data/{MOD}/loot_table/blocks/{name}.json"] = _json(
            herb_loot(name)
        )
    for item in ITEMS:
        files[f"data/{MOD}/horizon/item/{item}.json"] = _json(ITEM_DECLS[item])
        files[f"assets/{MOD}/items/{item}.json"] = _json(
            {"model": {"type": "minecraft:model", "model": f"{MOD}:item/{item}"}}
        )
    for name, recipe in RECIPES.items():
        files[f"data/{MOD}/recipe/{name}.json"] = _json(recipe)
    for name, tag in TAGS.items():
        files[name] = _json(tag)
    files[f"data/{MOD}/horizon/creative_tab/{MOD}.json"] = _json(
        {
            "title": "itemGroup.rootsclassic",
            "icon": f"{MOD}:dragons_eye",
            "items": [f"{MOD}:{name}" for name in HERBS + ITEMS],
        }
    )
    files[f"assets/{MOD}/lang/en_us.json"] = _json(
        {key: lang[key] for key in LANG_KEYS if key in lang}
    )
    return files


def _json(value: object) -> bytes:
    return (json.dumps(value, indent=2) + "\n").encode()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jar", type=Path, default=DEFAULT_JAR)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    digest = hashlib.sha1(args.jar.read_bytes()).hexdigest()
    if digest != JAR_SHA1:
        print(f"{args.jar}: SHA-1 {digest} is not the ATM10 file {JAR_SHA1}", file=sys.stderr)
        return 1

    with zipfile.ZipFile(args.jar) as jar:
        lang = json.loads(jar.read(f"assets/{MOD}/lang/en_us.json"))
        wanted = generated(lang)
        for name in VERBATIM:
            wanted[name] = jar.read(name)

    missing = [key for key in LANG_KEYS if key not in lang]
    if missing:
        print(f"the jar's lang has no key {missing}", file=sys.stderr)
        return 1

    changed = 0
    for name, data in sorted(wanted.items()):
        path = ROOT / name
        current = path.read_bytes() if path.exists() else None
        if current == data:
            continue
        changed += 1
        print(("would write " if args.check else "write ") + name)
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    print(
        f"{len(wanted)} files, {changed} {'pending' if args.check else 'written'}"
        f" (jar sha1 {digest})"
    )
    return 1 if args.check and changed else 0


if __name__ == "__main__":
    raise SystemExit(main())
