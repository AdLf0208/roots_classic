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
//! Slice 2 adds the powder chain that makes the herbs survival-obtainable:
//!
//! - `Powder` (an [`ItemPart`] on `rootsclassic:mutating_powder`): the jar's `MutatingPowderItem`.
//!   A four-block stepped ray names a block, the 5×5×5 box around it is scanned for item entities,
//!   and when the box's stacks are exactly one mutation's inputs the block becomes the herb, the
//!   entities are discarded and the recipe's side effect runs.
//! - `GrowthPowder` (on `rootsclassic:growth_powder`): the jar's `GrowthPowderItem`. Dirt becomes
//!   grass, water with air above grows a lily pad, and anything else gets one bone-meal growth.
//!
//! The pure rules live in [`runtime`], copied byte for byte from the retired `.hnmod` for slice 1;
//! this file is the glue only. The carried content (`assets/`, `data/`) is in this same package, so
//! the herbs, items and recipes arrive with the code instead of a second download.
pub mod runtime;

use std::sync::Mutex;
use std::sync::OnceLock;

use mod_api::{
    self, ActiveEffect, BlockUpdateFlags, Config, ConfigKind, ConfigLoadingEvent,
    ConsumeEffectEvent, EffectKey, Hand, Hooks, Host, HostSide, HostTransaction, InteractionResult,
    ItemKey, ItemPart, ItemPlace, ItemResource, ItemStack, LevelRef, LootDropsEvent, PlayerRef,
    RandomSource, RegisterConfigsEvent, Registrar, RegistrationContext, ServerHost, Tag,
    UseItemEvent, UseOnEvent,
};

/// This mod's id, which the manifest and the config file both use.
const MOD_ID: &str = "rootsclassic";

/// The consume effect kind the jar's food items carry (`registry/RootsFoods`).
const HEAL: &str = "rootsclassic:heal";

/// The jar's global loot condition: a shears never forages.
const SHEARS: &str = "minecraft:shears";

/// `MutatingPowderItem`'s item, and its recipe's prerequisite.
const MUTATING_POWDER: &str = "rootsclassic:mutating_powder";
/// `GrowthPowderItem`'s item.
const GROWTH_POWDER: &str = "rootsclassic:growth_powder";

/// The NeoForge persistent-data key the midnight bloom writes (`Const.NBT_SKIP_TICKS`).
const SKIP_TICKS: &str = "rootsclassic:RMOD_skipTicks";

/// The blindness a radiant daisy puts on the player: 1200 ticks, amplifier 0.
const BLINDNESS_TICKS: i32 = 1200;

/// The fire a flare orchid puts on the player: `igniteForSeconds(20)`.
const FLARE_FIRE_TICKS: i32 = 20 * 20;

/// The two powder items and the effect they apply, resolved once at registration.
struct PowderIds {
    mutating: ItemKey,
    growth: ItemKey,
    blindness: EffectKey,
}

static POWDER: OnceLock<PowderIds> = OnceLock::new();

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
        // Slice 2: the two powders are Parts of their own items, so the game calls them only for
        // those stacks and the port never has to ask which item was used.
        let powder = PowderIds {
            mutating: r.item_key(MUTATING_POWDER),
            growth: r.item_key(GROWTH_POWDER),
            blindness: r.effect_key("minecraft:blindness"),
        };
        r.item_part(powder.mutating, Powder);
        r.item_part(powder.growth, GrowthPowder);
        let _ = POWDER.set(powder);
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

/// The mutating powder's `ItemPart`: the jar's `MutatingPowderItem`. The game calls it only for
/// `rootsclassic:mutating_powder`, so the glue never asks which item was used.
struct Powder;

#[mod_api::horizon_part]
impl ItemPart for Powder {
    /// `Item.use`: ray-cast four blocks, scan the 5×5×5 box, and mutate the flower when the box
    /// holds exactly one recipe's inputs. Upstream answers `SUCCESS` on both sides, so the arm
    /// swings even when nothing matched; the powder is spent either way.
    fn use_item(
        &self,
        host: HostSide<'_>,
        event: &mut UseItemEvent<'_>,
    ) -> Option<InteractionResult> {
        let HostSide::Server(host) = host else {
            return Some(InteractionResult::Success);
        };
        let ids = POWDER.get()?;
        mutate(host, ids, event);
        Some(InteractionResult::SuccessServer)
    }
}

/// The growth powder's `ItemPart`: the jar's `GrowthPowderItem.useOn`.
struct GrowthPowder;

#[mod_api::horizon_part]
impl ItemPart for GrowthPowder {
    /// Dirt becomes grass, water with air above grows a lily pad, and anything else gets one
    /// bone-meal growth; the powder is spent only when the world changed.
    ///
    /// Upstream answers `PASS` unconditionally. Here a `PASS` lets the click fall through and be
    /// re-issued, which runs this handler twice and spends two powders for one growth (measured:
    /// 3 powders became 1 on one click). Answering `SuccessServer` when the powder acted ends the
    /// click after the one growth; a click that grew nothing still passes, so the block's own use
    /// runs exactly as upstream leaves it.
    fn use_on(&self, host: HostSide<'_>, event: &mut UseOnEvent<'_>) -> Option<InteractionResult> {
        let HostSide::Server(host) = host else {
            return Some(InteractionResult::Pass);
        };
        if grow(host, event) {
            Some(InteractionResult::SuccessServer)
        } else {
            Some(InteractionResult::Pass)
        }
    }
}

/// `MutatingPowderItem.use` on the server: the ray, the box, the recipe and its side effect.
fn mutate(host: &mut dyn ServerHost, ids: &PowderIds, event: &UseItemEvent<'_>) {
    let Some(player) = host.player(event.player) else {
        return;
    };
    let Some(level) = player.level(&*host) else {
        return;
    };
    let entity = player.entity();
    let Some(eye) = entity.eye_position(&*host) else {
        return;
    };
    let Some(rotation) = entity.rotation(&*host) else {
        return;
    };
    let look = look_vector(rotation[0], rotation[1]);
    let target = ray_target(&*host, level, eye, look);
    let (min, max) = mutation_box(target);
    let Some(entities) = level.entities_in(&*host, min, max) else {
        return;
    };
    let mut items = Vec::new();
    let mut found = Vec::new();
    for candidate in entities {
        let Some(item) = host.item_entity(candidate) else {
            continue;
        };
        let Some(stack) = item.stack(&*host) else {
            continue;
        };
        found.push(stack.item().id(&*host));
        items.push(candidate);
    }
    let effects = effect_ids(&*host, player);
    let base = block_name(&*host, level, target).unwrap_or_default();
    let dimension = level.dimension().id(&*host).unwrap_or_default();
    let below2 =
        block_name(&*host, level, [target[0], target[1] - 2, target[2]]).unwrap_or_default();
    let ring: [String; 8] =
        neighbours(target).map(|pos| block_name(&*host, level, pos).unwrap_or_default());
    let ring: [&str; 8] = ring.each_ref().map(String::as_str);
    let item_refs: Vec<&str> = found.iter().map(String::as_str).collect();
    let effect_refs: Vec<&str> = effects.iter().map(String::as_str).collect();
    let scene = runtime::MutagenScene {
        base: &base,
        dimension: &dimension,
        day_time: level.day_time(&*host).unwrap_or_default(),
        below2: &below2,
        neighbours: ring,
        items: &item_refs,
        effects: &effect_refs,
    };
    let Some(recipe) = runtime::mutation(&scene) else {
        spend(host, event.player, event.hand, event.stack);
        return;
    };
    let Some(state) = host.block_state_id(recipe.result()) else {
        return;
    };
    if !matches!(level.set_block(host, target, state, update_all()), Ok(true)) {
        return;
    }
    // `MutagenRecipe.matches` guarantees the box holds exactly the recipe's inputs, so every
    // entity the scan found is one this mutation consumed.
    for entity in items {
        entity.discard(host);
    }
    crafted(host, ids, player, recipe);
    spend(host, event.player, event.hand, event.stack);
}

/// `MutagenRecipe.onCrafted` for the recipe that matched.
fn crafted(
    host: &mut dyn ServerHost,
    ids: &PowderIds,
    player: PlayerRef,
    recipe: runtime::Mutation,
) {
    match recipe {
        runtime::Mutation::FlareOrchid => {
            // `player.igniteForSeconds(20)`.
            let _ = player
                .entity()
                .set_remaining_fire_ticks(host, FLARE_FIRE_TICKS);
        }
        runtime::Mutation::MidnightBloom => {
            // `player.getPersistentData().putInt(Const.NBT_SKIP_TICKS, 200)`.
            let mut data = player.persistent_data(&*host).unwrap_or_default();
            data.insert(SKIP_TICKS.into(), Tag::Int(200));
            let _ = player.set_persistent_data(host, data);
        }
        runtime::Mutation::RadiantDaisy => {
            // `new MobEffectInstance(MobEffects.BLINDNESS, 1200, 0)`: ambient false, particles and
            // icon shown, as the two-argument constructor leaves them.
            let Some(living) = host.living(player.entity()) else {
                return;
            };
            let effect = ActiveEffect::new(ids.blindness, BLINDNESS_TICKS, 0, false, true, true);
            let _ = living.add_effect(host, &effect);
        }
    }
}

/// `GrowthPowderItem.useOn` on the server.
fn grow(host: &mut dyn ServerHost, event: &UseOnEvent<'_>) -> bool {
    let Some(player) = host.player(event.player) else {
        return false;
    };
    let Some(level) = player.level(&*host) else {
        return false;
    };
    let pos = event.pos;
    let above = [pos[0], pos[1] + 1, pos[2]];
    let block = block_name(host, level, pos).unwrap_or_default();
    let over = block_name(host, level, above).unwrap_or_default();
    let grew = match runtime::growth(&block, &over) {
        Some(runtime::Growth::Grass) => set(host, level, pos, "minecraft:grass_block"),
        // Upstream places the lily pad and then falls out to `return false`, so the powder is
        // never spent and one powder grows lily pads forever. The port returns success.
        Some(runtime::Growth::LilyPad) => set(host, level, above, "minecraft:lily_pad"),
        // `state.randomTick` on a bonemealable block, as the closest supported API: `bone_meal`
        // refuses a block that cannot grow and reports whether something did.
        None => level.bone_meal(host, pos),
    };
    if grew {
        spend(host, event.player, event.hand, event.stack);
    }
    grew
}

/// Write `id` at `pos` with vanilla's `setBlockAndUpdate` flags; whether it changed.
fn set(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3], id: &str) -> bool {
    let Some(state) = host.block_state_id(id) else {
        return false;
    };
    matches!(level.set_block(host, pos, state, update_all()), Ok(true))
}

/// `Block.UPDATE_ALL`: `setBlockAndUpdate`'s flags (`NEIGHBORS | CLIENTS`).
fn update_all() -> BlockUpdateFlags {
    BlockUpdateFlags::NEIGHBORS | BlockUpdateFlags::CLIENTS
}

/// Keyed by item: `stack.shrink(1)`, unless the player is creative (`ItemPlace::extract` gives
/// without losing any for a creative player).
fn spend(host: &mut dyn ServerHost, player: u128, hand: Hand, stack: &ItemStack) {
    let place = ItemPlace::PlayerHand { player, hand };
    let resource = ItemResource::of(stack);
    let _ = host.transaction(|host, tx| {
        place.extract(host, tx, &resource, 1);
        Ok::<(), ()>(())
    });
}

/// The block the powder's stepped ray names: the first non-air sample, or the last sample when
/// the four blocks are empty (`RootsUtil.getRayTrace`).
fn ray_target(host: &dyn Host, level: LevelRef, eye: [f64; 3], look: [f64; 3]) -> [i32; 3] {
    let mut last = [0, 0, 0];
    for pos in runtime::ray_steps(eye, look, runtime::POWDER_REACH) {
        last = pos;
        let Some(state) = level.block_state(host, pos) else {
            continue;
        };
        let Some(text) = host.block_state_string(state) else {
            continue;
        };
        if split_state(&text).0 != "minecraft:air" {
            return pos;
        }
    }
    last
}

/// The id of the block at `pos`, without its properties.
fn block_name(host: &dyn Host, level: LevelRef, pos: [i32; 3]) -> Option<String> {
    let state = level.block_state(host, pos)?;
    let text = host.block_state_string(state)?;
    Some(split_state(&text).0.to_owned())
}

/// The ids of the effects `player` carries.
fn effect_ids(host: &dyn Host, player: PlayerRef) -> Vec<String> {
    let Some(living) = host.living(player.entity()) else {
        return Vec::new();
    };
    let Some(effects) = living.effects(host) else {
        return Vec::new();
    };
    effects
        .into_iter()
        .map(|effect| effect.id.id(host))
        .collect()
}

/// `LivingEntity.getLookAngle()` from the entity's rotation in degrees.
fn look_vector(yaw: f32, pitch: f32) -> [f64; 3] {
    let yaw = f64::from(yaw).to_radians();
    let pitch = f64::from(pitch).to_radians();
    let flat = pitch.cos();
    [-yaw.sin() * flat, -pitch.sin(), yaw.cos() * flat]
}

/// The eight horizontal neighbours, in the order upstream tests them:
/// east, west, north, south, east+north, west+south, north+west, south+east.
fn neighbours(pos: [i32; 3]) -> [[i32; 3]; 8] {
    let [x, y, z] = pos;
    [
        [x + 1, y, z],
        [x - 1, y, z],
        [x, y, z - 1],
        [x, y, z + 1],
        [x + 1, y, z - 1],
        [x - 1, y, z + 1],
        [x - 1, y, z - 1],
        [x + 1, y, z + 1],
    ]
}

/// `MutatingPowderItem`'s item-entity box: `pos ± 2` on each axis (`pos - 2 .. pos + 3`).
fn mutation_box(pos: [i32; 3]) -> ([f64; 3], [f64; 3]) {
    let at = |axis: usize| f64::from(pos[axis]);
    let low = runtime::MUTATION_BOX;
    let high = runtime::MUTATION_BOX + 1.0;
    (
        [at(0) - low, at(1) - low, at(2) - low],
        [at(0) + high, at(1) + high, at(2) + high],
    )
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

    #[test]
    fn the_eight_neighbours_are_the_horizontal_ring_in_upstream_order() {
        assert_eq!(
            neighbours([10, 64, 10]),
            [
                [11, 64, 10],
                [9, 64, 10],
                [10, 64, 9],
                [10, 64, 11],
                [11, 64, 9],
                [9, 64, 11],
                [9, 64, 9],
                [11, 64, 11],
            ]
        );
    }

    #[test]
    fn the_mutation_box_is_the_five_block_cube() {
        // `new AABB(pos - 2, pos + 3)` is five blocks across, inclusive of both corners.
        assert_eq!(
            mutation_box([10, 64, 10]),
            ([8.0, 62.0, 8.0], [13.0, 67.0, 13.0])
        );
    }

    #[test]
    fn the_look_vector_follows_the_rotation() {
        let close =
            |got: [f64; 3], want: [f64; 3]| got.iter().zip(want).all(|(a, b)| (a - b).abs() < 1e-9);
        // Yaw 0, pitch 0 looks along +Z.
        assert!(close(look_vector(0.0, 0.0), [0.0, 0.0, 1.0]));
        // Yaw 90 looks along -X, as vanilla's `getLookAngle` does.
        assert!(close(look_vector(90.0, 0.0), [-1.0, 0.0, 0.0]));
        // Pitch 90 looks straight down.
        assert!(close(look_vector(0.0, 90.0), [0.0, -1.0, 0.0]));
    }
}
