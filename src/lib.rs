//! Roots Classic for Horizon — the one `impl Hooks` at the crate root.
//!
//! Slice 1 of the content half: the three herbs and the loop they feed.
//!
//! - `register_configs` + `config_loading`: `config/rootsclassic-common.toml`, the jar's own
//!   `[items]` chances, written with its defaults when the file is missing.
//! - `loot_drops`: the jar's global loot modifier. A broken `short_grass`, a fully grown crop, a
//!   ripe `nether_wart`, a `chorus_flower` or leaves that dropped no leaf block may add its herb.
//! - `consume_effect`: the mod's own `rootsclassic:heal` kind, the heal `RootsFoodItem` applies.
//!
//! The pure rules live in [`runtime`], copied byte for byte from the retired `.hnmod`; this file
//! is the glue only. The carried content (`assets/`, `data/`) is in this same package, so the
//! herbs, items and recipes arrive with the code instead of a second download.
pub mod runtime;

use std::sync::Mutex;
use std::sync::OnceLock;

use mod_api::{
    self, Config, ConfigKind, ConfigLoadingEvent, ConsumeEffectEvent, Hooks, HostSide, ItemKey,
    ItemStack, LootDropsEvent, RandomSource, RegisterConfigsEvent, Registrar, RegistrationContext,
    ServerHost, Tag,
};

/// This mod's id, which the manifest and the config file both use.
const MOD_ID: &str = "rootsclassic";

/// The consume effect kind the jar's food items carry (`registry/RootsFoods`).
const HEAL: &str = "rootsclassic:heal";

/// The jar's global loot condition: a shears never forages.
const SHEARS: &str = "minecraft:shears";

/// The item keys the runtime's rules name, resolved once at registration.
///
/// The runtime names items by id (`rootsclassic:old_root`); the API identifies them by `ItemKey`.
/// Every one of these is declared by this package's own `data/`, and a requested key is validated
/// after all declarations, so a missing item refuses the mod instead of failing silently.
struct Ids {
    old_root: ItemKey,
    verdant_sprig: ItemKey,
    infernal_bulb: ItemKey,
    dragons_eye: ItemKey,
    berries: [ItemKey; runtime::BERRIES.len()],
    shears: ItemKey,
}

static IDS: OnceLock<Ids> = OnceLock::new();

/// The `[items]` chances the game loaded. `ConfigKind::Common` loads once per process, before any
/// world, exactly as NeoForge loads the jar's common config; the lock also carries a reload.
static CHANCES: Mutex<Option<runtime::Chances>> = Mutex::new(None);

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Resolve the keys the rules compare. The herbs the forage table rolls are this package's
    /// own items, so the requests are satisfied by the content beside the code.
    fn register(&self, r: &mut dyn Registrar, _cx: &RegistrationContext) {
        let ids = Ids {
            old_root: r.item_key(runtime::OLD_ROOT),
            verdant_sprig: r.item_key(runtime::VERDANT_SPRIG),
            infernal_bulb: r.item_key(runtime::INFERNAL_BULB),
            dragons_eye: r.item_key(runtime::DRAGONS_EYE),
            berries: runtime::BERRIES.map(|berry| r.item_key(berry)),
            shears: r.item_key(SHEARS),
        };
        let _ = IDS.set(ids);
    }

    /// Register `config/rootsclassic-common.toml` — the jar's own file name — as this mod's
    /// common config. The game writes `default` there when the file is missing, as NeoForge's
    /// `ModContainer.registerConfig` does, so a first run leaves the jar's defaults on disk.
    fn register_configs(&self, _host: HostSide, event: &mut RegisterConfigsEvent<'_>) {
        let default = default_config(runtime::Chances::default());
        event
            .configs
            .push(Config::new(MOD_ID, ConfigKind::Common, &default).file(runtime::CONFIG_FILE));
    }

    /// The game read a config; ours it is `rootsclassic`, so parse its `[items]` section. Every
    /// mod hears every config, so the id is checked.
    fn config_loading(&self, _host: HostSide, event: &mut ConfigLoadingEvent<'_>) {
        if event.config.mod_id == MOD_ID {
            loaded(&event.config.text);
        }
    }

    /// A block broke or a mob died and `event.drops` are what it rolled. Only a block has a forage
    /// table in this mod, so a death returns at once. The jar's `DropModifier.BlockDropModifier`:
    /// a broken `short_grass`, a crop at its last age, a ripe `nether_wart`, a `chorus_flower`, or
    /// leaves that dropped no leaf block, add one herb at their `1/N` config chance.
    fn loot_drops(&self, host: &mut dyn ServerHost, event: &mut LootDropsEvent<'_>) {
        let Some(ids) = IDS.get() else {
            return;
        };
        let context = event.context;
        let Some((_pos, state)) = context.block else {
            return;
        };
        // A shears is the jar's global condition: shearing a leaf must not also forage one.
        if context.tool.is_some_and(|tool| tool.item() == ids.shears) {
            return;
        }
        // `minecraft:wheat[age=7]` in one read: the block's id and its own `age` property.
        let Some(text) = host.block_state_string(state) else {
            return;
        };
        let (name, age) = split_state(&text);
        // The other half of the leaves rule: a block that already dropped itself (shears, silk
        // touch) forages nothing. `Block.asItem` is the block's own item, so this stays general.
        let dropped_itself = host
            .block_item(state.block())
            .is_some_and(|item| event.drops.iter().any(|stack| stack.item() == item));
        let Some(forage) = runtime::classify(name, age, dropped_itself) else {
            return;
        };
        let chance = runtime::chance(chances(), forage);
        if chance == 0 {
            return;
        }
        let Some(level) = host.level(context.dimension) else {
            return;
        };
        // `random.nextInt(chance) == 0`, drawn from the level's own stream in vanilla's order.
        let bound = i32::try_from(chance).unwrap_or(i32::MAX);
        let Some(Ok(draw)) = level.with_random(host, |random| random.next_int_bound(bound)) else {
            return;
        };
        if !runtime::rolls(chance, u32::try_from(draw).unwrap_or(0)) {
            return;
        }
        let item = match forage {
            runtime::Forage::OldRoot => ids.old_root,
            runtime::Forage::VerdantSprig => ids.verdant_sprig,
            runtime::Forage::InfernalBulb => ids.infernal_bulb,
            runtime::Forage::DragonsEye => ids.dragons_eye,
            runtime::Forage::Berry => {
                // `getRandomElement`: one uniform draw over the tag's five entries.
                let len = i32::try_from(runtime::BERRIES.len()).unwrap_or(1);
                let pick = level
                    .with_random(host, |random| random.next_int_bound(len))
                    .and_then(Result::ok)
                    .unwrap_or(0);
                let pick = usize::try_from(pick).unwrap_or(0);
                ids.berries.get(pick).copied().unwrap_or(ids.berries[0])
            }
        };
        if let Some(stack) = ItemStack::new(item, 1) {
            event.drops.push(stack);
        }
    }

    /// A consumable's effect of a mod's own kind: `rootsclassic:heal` carries the jar's
    /// `RootsFoodItem` heal amount, which no vanilla consume effect states exactly.
    fn consume_effect(&self, host: &mut dyn ServerHost, event: &mut ConsumeEffectEvent<'_>) {
        if event.kind != HEAL {
            return;
        }
        let Some(player) = host.players().acting_player() else {
            return;
        };
        let Some(living) = host.living(player.entity()) else {
            return;
        };
        let Some(current) = living.health(&*host) else {
            return;
        };
        let target = runtime::heal_target(current, heal_amount(event.data));
        if target <= current {
            return;
        }
        // `LivingEntity.heal`'s net effect: the game caps the result at the player's maximum.
        let _ = living.set_health(host, target);
    }
}

/// The config in force, or the jar's defaults before (or without) a load.
fn chances() -> runtime::Chances {
    CHANCES
        .lock()
        .map(|guard| guard.unwrap_or_default())
        .unwrap_or_default()
}

/// Takes the text the game loaded for this mod's config file.
fn loaded(text: &str) {
    if let Ok(mut guard) = CHANCES.lock() {
        *guard = Some(runtime::Chances::from_toml(text));
    }
}

/// A block state string (`minecraft:wheat[age=7]`) as the rules want it: the block's id and its
/// `age` property when it has one.
fn split_state(text: &str) -> (&str, Option<u8>) {
    let Some((name, properties)) = text.split_once('[') else {
        return (text, None);
    };
    let age = properties
        .trim_end_matches(']')
        .split(',')
        .find_map(|property| {
            let (key, value) = property.split_once('=')?;
            (key == "age").then(|| value.parse::<u8>().ok())?
        });
    (name, age)
}

/// The `amount` a `rootsclassic:heal` effect payload carries. The JSON's number arrives as a
/// `Double` or an `Int`; every numeric tag is accepted and a missing one heals nothing.
fn heal_amount(data: &Tag) -> f32 {
    match data.get("amount") {
        Some(Tag::Double(bits)) => f64::from_bits(*bits) as f32,
        Some(Tag::Float(bits)) => f32::from_bits(*bits),
        Some(Tag::Int(value)) => *value as f32,
        Some(Tag::Long(value)) => *value as f32,
        Some(Tag::Short(value)) => f32::from(*value),
        Some(Tag::Byte(value)) => f32::from(*value),
        _ => 0.0,
    }
}

/// The file NeoForge generates for the jar's common config, key for key, for the keys this slice
/// reads. The comments are the jar's own.
fn default_config(chances: runtime::Chances) -> String {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_state_string_yields_its_id_and_age() {
        assert_eq!(
            split_state("minecraft:wheat[age=7]"),
            ("minecraft:wheat", Some(7))
        );
        assert_eq!(
            split_state("minecraft:beetroots[age=3]"),
            ("minecraft:beetroots", Some(3))
        );
        assert_eq!(
            split_state("minecraft:oak_leaves[distance=7,persistent=true]"),
            ("minecraft:oak_leaves", None)
        );
        assert_eq!(split_state("minecraft:stone"), ("minecraft:stone", None));
        assert_eq!(
            split_state("minecraft:carrots[age=0]"),
            ("minecraft:carrots", Some(0))
        );
    }

    #[test]
    fn an_age_outside_a_byte_is_no_age() {
        // A property the rules cannot use must read as absent, not as a wrong age.
        assert_eq!(split_state("minecraft:wheat[age=999]").1, None);
    }

    #[test]
    fn the_heal_amount_comes_from_the_effect_payload() {
        let double = Tag::compound([("amount", Tag::Double(2.0f64.to_bits()))]);
        assert_eq!(heal_amount(&double), 2.0);
        let int = Tag::compound([("amount", Tag::Int(5))]);
        assert_eq!(heal_amount(&int), 5.0);
        let float = Tag::compound([("amount", Tag::Float(1.5f32.to_bits()))]);
        assert_eq!(heal_amount(&float), 1.5);
        assert_eq!(heal_amount(&Tag::compound([("other", Tag::Int(1))])), 0.0);
        assert_eq!(heal_amount(&Tag::Int(3)), 0.0);
    }

    #[test]
    fn the_default_config_reads_back_as_the_defaults() {
        // The file the game writes must parse into the values it was written from.
        let text = default_config(runtime::Chances::default());
        assert_eq!(
            runtime::Chances::from_toml(&text),
            runtime::Chances::default()
        );
        assert_eq!(runtime::CONFIG_FILE, "rootsclassic-common.toml");
    }

    #[test]
    fn a_loaded_config_overrides_the_defaults() {
        loaded("[items]\noldRootDropChance = 2\nberriesDropChance = 0\n");
        let loaded_chances = chances();
        assert_eq!(loaded_chances.old_root(), 2);
        assert_eq!(loaded_chances.berries(), 0);
        assert_eq!(
            loaded_chances.verdant_sprig(),
            30,
            "an unread key keeps its default"
        );
        loaded("");
        assert_eq!(chances(), runtime::Chances::default());
    }
}
