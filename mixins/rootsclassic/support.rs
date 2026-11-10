// Game-side glue for the Roots Classic herbs slice: the forage a broken block
// rolls (API 75) and the healing a `rootsclassic:heal` consumable reaches
// (API 74). The pure rules live in the `runtime` module.

use crate::game::rootsclassic as rules;
use horizon_client::game::native_hooks::NativeLootDrops;
use horizon_client::items::ItemStack;
use horizon_core::random::RandomSource;
use std::sync::OnceLock;

/// The consume effect this slice answers; its `data` carries `amount`.
const HEAL: &str = "rootsclassic:heal";

/// `Game::native_loot_drops` head: the jar's global loot modifier. A broken
/// `short_grass`, a fully grown crop, a ripe `nether_wart`, a `chorus_flower`
/// or leaves that dropped no leaf block may add its one herb, at the chance
/// the config gives it.
pub(super) fn on_loot_drops(
    game: &mut crate::game::Game<'_>,
    context: &NativeLootDrops<'_>,
    drops: &mut Vec<ItemStack>,
) {
    let Some((_pos, state)) = context.block else {
        return;
    };
    // The jar's global condition: a shears never forages (its own leaves rule
    // comes first), and neither does a block a shears peeled.
    if context
        .tool
        .is_some_and(|tool| &*tool.item == "minecraft:shears")
    {
        return;
    }
    let Some(block) = game.pack.assets.registry.state(state) else {
        return;
    };
    let name = block.name.clone();
    let age = block
        .properties
        .get("age")
        .and_then(|age| age.parse::<u8>().ok());
    let dropped_itself = drops.iter().any(|stack| stack.item.as_ref() == name.as_str());
    let Some(forage) = rules::classify(&name, age, dropped_itself) else {
        return;
    };
    let chance = rules::chance(chances(), forage);
    if chance == 0 {
        return;
    }
    let Some(random) = game.native_level_random(context.dimension) else {
        return;
    };
    let Ok(draw) = random.next_int_bound(i32::try_from(chance).unwrap_or(i32::MAX)) else {
        return;
    };
    if !rules::rolls(chance, u32::try_from(draw).unwrap_or(0)) {
        return;
    }
    let item = match forage {
        rules::Forage::OldRoot => rules::OLD_ROOT,
        rules::Forage::VerdantSprig => rules::VERDANT_SPRIG,
        rules::Forage::InfernalBulb => rules::INFERNAL_BULB,
        rules::Forage::DragonsEye => rules::DRAGONS_EYE,
        rules::Forage::Berry => {
            // `getRandomElement`: one uniform draw over the tag's five entries.
            let pick = random
                .next_int_bound(i32::try_from(rules::BERRIES.len()).unwrap_or(1))
                .unwrap_or(0);
            rules::berry(usize::try_from(pick).unwrap_or(0))
        }
    };
    drops.push(ItemStack::new(item, 1));
}

/// `Game::native_consume_effect` head: a consumable's own effect kind. The
/// herbs heal a fixed amount on finishing (`RootsFoodItem.finishUsingItem`),
/// which no vanilla consume effect states exactly.
pub(super) fn on_consume_effect(
    game: &mut crate::game::Game<'_>,
    kind: &str,
    data: &serde_json::Value,
) {
    if kind != HEAL {
        return;
    }
    let Some(player) = game.native_acting_player() else {
        return;
    };
    let amount = data
        .get("amount")
        .and_then(serde_json::Value::as_f64)
        .unwrap_or(0.0) as f32;
    let target = rules::heal_target(player.health, amount);
    if target <= player.health {
        return;
    }
    let _ = game.native_set_player_status(player.uuid, Some(target), None, None);
}

/// The `[items]` chances, read once per process: the config file does not
/// change under a running server, as NeoForge loads it at start. A missing
/// file is written with the jar's defaults, as the jar's own config does.
fn chances() -> rules::Chances {
    static CHANCES: OnceLock<rules::Chances> = OnceLock::new();
    *CHANCES.get_or_init(read_chances)
}

/// Reads `<config>/rootsclassic-common.toml`, or leaves the defaults on disk.
fn read_chances() -> rules::Chances {
    let Ok(dir) = crate::game::Game::native_config_dir() else {
        return rules::Chances::default();
    };
    let path = dir.join(rules::CONFIG_FILE);
    match std::fs::read_to_string(&path) {
        Ok(text) => rules::Chances::from_toml(&text),
        Err(_) => {
            let defaults = rules::Chances::default();
            let _ = std::fs::write(&path, default_config(defaults));
            defaults
        }
    }
}

/// The file the jar's config writes on first run, for the keys this slice reads.
fn default_config(chances: rules::Chances) -> String {
    format!(
        "\
# Settings related to actual gameplay-affecting features
[items]
\t# Old Roots will drop from tall grass with a 1/oldRootDropChance probability
\toldRootDropChance = {}
\t# Verdant Sprigs will drop from grown crops with a 1/verdantSprigDropChance probability
\tverdantSprigDropChance = {}
\t# Infernal Bulbs will drop from nether wart with a 1/infernalBulbDropChance probability
\tinfernalStemDropChance = {}
\t# Dragon's Eyes will drop from chorus flowers with a 1/dragonsEyeDropChance probability
\tdragonsEyeDropChance = {}
\t# Berries will drop from oak leaves with a 1/berriesDropChance probability
\tberriesDropChance = {}
",
        chances.old_root(),
        chances.verdant_sprig(),
        chances.infernal_bulb(),
        chances.dragons_eye(),
        chances.berries(),
    )
}
