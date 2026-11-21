// The pure rules for Roots Classic slice 1: the forage table the jar's global
// loot modifier rolls, the config it reads, and the numbers its food items
// carry. This file is both the standalone Cargo library and the injected
// `game::rootsclassic` module (a support module may not carry `//!` file
// attributes), so its header is plain comments.
//
// No world access, no game types: `support.rs` reads the block, the tool and
// the config file and calls these functions. Upstream is
// `lootmodifiers/DropModifier.BlockDropModifier` and `registry/RootsFoods`.

/// The old root a short grass block may hide.
pub const OLD_ROOT: &str = "rootsclassic:old_root";
/// The verdant sprig a fully grown crop may hide.
pub const VERDANT_SPRIG: &str = "rootsclassic:verdant_sprig";
/// The infernal bulb a ripe nether wart may hide.
pub const INFERNAL_BULB: &str = "rootsclassic:infernal_bulb";
/// The dragon's eye a chorus flower may hide.
pub const DRAGONS_EYE: &str = "rootsclassic:dragons_eye";

/// `#rootsclassic:berries`, in the jar's tag order: the leaves roll picks one.
pub const BERRIES: [&str; 5] = [
    "rootsclassic:nightshade",
    "rootsclassic:blackcurrant",
    "rootsclassic:redcurrant",
    "rootsclassic:whitecurrant",
    "rootsclassic:elderberry",
];

/// The config file NeoForge generates for the jar's common config.
pub const CONFIG_FILE: &str = "rootsclassic-common.toml";

/// The jar's own ceiling for a `defineInRange(..., 0, 32767)` chance.
const MAX_CHANCE: u32 = 32_767;

/// The five `1/N` chances the jar's `[items]` section carries, with its
/// defaults: 0 never rolls, 1 always does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Chances {
    old_root: u32,
    verdant_sprig: u32,
    infernal_bulb: u32,
    dragons_eye: u32,
    berries: u32,
}

impl Default for Chances {
    /// `config/RootsConfig.Common`: the defaults the jar writes on first run.
    fn default() -> Self {
        Self {
            old_root: 40,
            verdant_sprig: 30,
            infernal_bulb: 20,
            dragons_eye: 10,
            berries: 25,
        }
    }
}

impl Chances {
    /// The `oldRootDropChance` a short grass break rolls against.
    #[must_use]
    pub fn old_root(self) -> u32 {
        self.old_root
    }

    /// The `verdantSprigDropChance` a grown crop rolls against.
    #[must_use]
    pub fn verdant_sprig(self) -> u32 {
        self.verdant_sprig
    }

    /// The `infernalStemDropChance` a ripe nether wart rolls against.
    #[must_use]
    pub fn infernal_bulb(self) -> u32 {
        self.infernal_bulb
    }

    /// The `dragonsEyeDropChance` a chorus flower rolls against.
    #[must_use]
    pub fn dragons_eye(self) -> u32 {
        self.dragons_eye
    }

    /// The `berriesDropChance` a leaf block rolls against.
    #[must_use]
    pub fn berries(self) -> u32 {
        self.berries
    }

    /// Reads the `[items]` section of a `rootsclassic-common.toml`, keeping
    /// each key's default when it is missing, unreadable or outside the jar's
    /// `0..=32767`. Other sections (`[magic]`, `[client]`) are ignored: this
    /// slice has no spells.
    #[must_use]
    pub fn from_toml(text: &str) -> Self {
        let mut chances = Self::default();
        let mut in_items = false;
        for line in text.lines() {
            // The file is key = value with `#` comments; no value quotes a `#`.
            let line = line.split('#').next().unwrap_or_default().trim();
            if line.is_empty() {
                continue;
            }
            if line.starts_with('[') {
                in_items = line == "[items]";
                continue;
            }
            if !in_items {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let Ok(value) = value.trim().parse::<i64>() else {
                continue;
            };
            let Ok(value) = u32::try_from(value) else {
                continue;
            };
            if value > MAX_CHANCE {
                continue;
            }
            match key.trim() {
                "oldRootDropChance" => chances.old_root = value,
                "verdantSprigDropChance" => chances.verdant_sprig = value,
                "infernalStemDropChance" => chances.infernal_bulb = value,
                "dragonsEyeDropChance" => chances.dragons_eye = value,
                "berriesDropChance" => chances.berries = value,
                // `barkKnifeBlockStripChance` and the `[magic]` keys are not
                // this slice's; ignoring them keeps a re-saved file usable.
                _ => {}
            }
        }
        chances
    }
}

/// What one kind of block break can forage.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Forage {
    /// Short grass hides an old root.
    OldRoot,
    /// A crop at its last age hides a verdant sprig.
    VerdantSprig,
    /// A ripe nether wart hides an infernal bulb.
    InfernalBulb,
    /// A chorus flower hides a dragon's eye.
    DragonsEye,
    /// Leaves that dropped no leaf block hide a berry.
    Berry,
}

/// The forage a broken block offers, before its chance roll.
///
/// `age` is the block's own `age` property, when it has one; `dropped_itself`
/// says the roll already produced the broken leaf block (shears or silk
/// touch), which upstream refuses for the berry roll.
#[must_use]
pub fn classify(block: &str, age: Option<u8>, dropped_itself: bool) -> Option<Forage> {
    match block {
        "minecraft:short_grass" => Some(Forage::OldRoot),
        "minecraft:wheat" | "minecraft:carrots" | "minecraft:potatoes" => {
            (age == Some(7)).then_some(Forage::VerdantSprig)
        }
        "minecraft:beetroots" => (age == Some(3)).then_some(Forage::VerdantSprig),
        "minecraft:nether_wart" => (age == Some(3)).then_some(Forage::InfernalBulb),
        "minecraft:chorus_flower" => Some(Forage::DragonsEye),
        _ if is_leaves(block) && !dropped_itself => Some(Forage::Berry),
        _ => None,
    }
}

/// The `1/N` chance `forage` rolls against.
#[must_use]
pub fn chance(chances: Chances, forage: Forage) -> u32 {
    match forage {
        Forage::OldRoot => chances.old_root,
        Forage::VerdantSprig => chances.verdant_sprig,
        Forage::InfernalBulb => chances.infernal_bulb,
        Forage::DragonsEye => chances.dragons_eye,
        Forage::Berry => chances.berries,
    }
}

/// `random.nextInt(chance) == 0`: one draw in `chance` hits. A chance of 0
/// never rolls (the config's "off"), 1 always does.
#[must_use]
pub fn rolls(chance: u32, draw: u32) -> bool {
    chance != 0 && draw.is_multiple_of(chance)
}

/// The berry a leaf roll drops: upstream takes a random entry of
/// `#rootsclassic:berries`, so a draw cycles the five.
#[must_use]
pub fn berry(draw: usize) -> &'static str {
    BERRIES[draw % BERRIES.len()]
}

/// The health a `rootsclassic:heal` consume effect reaches: the player's
/// health plus `amount`, or their health unchanged for a nonsense amount. The
/// game caps the result at the player's maximum.
#[must_use]
pub fn heal_target(current: f32, amount: f32) -> f32 {
    if amount.is_finite() && amount > 0.0 {
        current + amount
    } else {
        current
    }
}

/// A broken block is leaves when its id ends in `_leaves`, as every vanilla
/// leaf block does (upstream asks `instanceof LeavesBlock`).
fn is_leaves(block: &str) -> bool {
    block.ends_with("_leaves")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_the_jar() {
        let chances = Chances::default();
        assert_eq!(chances.old_root(), 40);
        assert_eq!(chances.verdant_sprig(), 30);
        assert_eq!(chances.infernal_bulb(), 20);
        assert_eq!(chances.dragons_eye(), 10);
        assert_eq!(chances.berries(), 25);
    }

    #[test]
    fn parses_every_items_key() {
        let text = "\
# Settings related to actual gameplay-affecting features
[items]
	oldRootDropChance = 7
	verdantSprigDropChance = 6
	infernalStemDropChance = 5
	dragonsEyeDropChance = 4
	berriesDropChance = 3
	barkKnifeBlockStripChance = 0.3
[magic]
	staffUses = 65
";
        let chances = Chances::from_toml(text);
        assert_eq!(chances.old_root(), 7);
        assert_eq!(chances.verdant_sprig(), 6);
        assert_eq!(chances.infernal_bulb(), 5);
        assert_eq!(chances.dragons_eye(), 4);
        assert_eq!(chances.berries(), 3);
    }

    #[test]
    fn magic_section_does_not_leak_into_the_items_keys() {
        // `staffUses` and the other [magic] keys share the file; none of them
        // may be read as a chance.
        let text = "[magic]\nstaffUses = 65\nefficiencyBonusUses = 32\n";
        let chances = Chances::from_toml(text);
        assert_eq!(chances, Chances::default());
    }

    #[test]
    fn a_missing_or_broken_value_keeps_its_default() {
        for text in [
            "oldRootDropChance = 70000\n",  // out of the jar's 0..=32767
            "oldRootDropChance = -4\n",     // negative
            "oldRootDropChance = always\n", // not a number
            "oldRootDropChance =\n",
            "[items]\n", // no keys at all
            "",
        ] {
            assert_eq!(
                Chances::from_toml(text).old_root(),
                40,
                "text {text:?} must keep the default"
            );
        }
    }

    #[test]
    fn zero_and_one_are_the_jar_s_off_and_always() {
        assert!(!rolls(0, 0), "chance 0 never rolls");
        assert!(rolls(1, 0), "chance 1 always rolls");
        assert!(rolls(1, 999));
    }

    #[test]
    fn a_roll_is_the_draw_modulo_the_chance() {
        // `random.nextInt(chance) == 0`: exactly one draw in `chance` hits.
        assert!(rolls(40, 0));
        assert!(!rolls(40, 39));
        assert!(rolls(40, 40));
        assert!(!rolls(40, 41));
        assert!(rolls(20, 120));
    }

    #[test]
    fn short_grass_forages_an_old_root() {
        assert_eq!(
            classify("minecraft:short_grass", None, false),
            Some(Forage::OldRoot)
        );
        // `tall_grass` is a DoublePlantBlock upstream, not a TallGrassBlock.
        assert_eq!(classify("minecraft:tall_grass", None, false), None);
        assert_eq!(classify("minecraft:grass", None, false), None);
    }

    #[test]
    fn only_a_fully_grown_crop_forages_a_verdant_sprig() {
        for (block, ripe) in [
            ("minecraft:wheat", 7),
            ("minecraft:carrots", 7),
            ("minecraft:potatoes", 7),
            ("minecraft:beetroots", 3),
        ] {
            assert_eq!(
                classify(block, Some(ripe), false),
                Some(Forage::VerdantSprig),
                "{block} at its last age"
            );
            assert_eq!(
                classify(block, Some(ripe - 1), false),
                None,
                "{block} one age short"
            );
            assert_eq!(classify(block, None, false), None, "{block} with no age");
        }
        assert_eq!(classify("minecraft:melon_stem", Some(7), false), None);
    }

    #[test]
    fn nether_wart_needs_its_last_age_and_a_chorus_flower_needs_nothing() {
        assert_eq!(
            classify("minecraft:nether_wart", Some(3), false),
            Some(Forage::InfernalBulb)
        );
        assert_eq!(classify("minecraft:nether_wart", Some(2), false), None);
        assert_eq!(
            classify("minecraft:chorus_flower", None, false),
            Some(Forage::DragonsEye)
        );
    }

    #[test]
    fn leaves_forage_a_berry_only_when_they_did_not_drop_themselves() {
        assert_eq!(
            classify("minecraft:oak_leaves", None, false),
            Some(Forage::Berry)
        );
        assert_eq!(
            classify("minecraft:azalea_leaves", None, false),
            Some(Forage::Berry)
        );
        // Shears, or a silk-touch roll, already dropped the leaf block.
        assert_eq!(classify("minecraft:oak_leaves", None, true), None);
        assert_eq!(classify("minecraft:oak_log", None, false), None);
    }

    #[test]
    fn nothing_else_forages() {
        for block in [
            "minecraft:stone",
            "minecraft:dirt",
            "minecraft:grass_block",
            "minecraft:poppy",
            "minecraft:oak_log",
            "rootsclassic:flare_orchid",
        ] {
            assert_eq!(classify(block, None, false), None, "{block}");
        }
    }

    #[test]
    fn the_chance_of_a_forage_kind_comes_from_its_config_key() {
        let chances = Chances {
            old_root: 1,
            verdant_sprig: 2,
            infernal_bulb: 3,
            dragons_eye: 4,
            berries: 5,
        };
        assert_eq!(chance(chances, Forage::OldRoot), 1);
        assert_eq!(chance(chances, Forage::VerdantSprig), 2);
        assert_eq!(chance(chances, Forage::InfernalBulb), 3);
        assert_eq!(chance(chances, Forage::DragonsEye), 4);
        assert_eq!(chance(chances, Forage::Berry), 5);
    }

    #[test]
    fn the_berry_tag_holds_the_five_berries_in_the_jar_s_order() {
        assert_eq!(BERRIES.len(), 5);
        assert_eq!(berry(0), "rootsclassic:nightshade");
        assert_eq!(berry(4), "rootsclassic:elderberry");
        assert_eq!(berry(5), berry(0), "the draw wraps");
    }

    #[test]
    fn healing_adds_the_amount_and_ignores_a_nonsense_one() {
        assert_eq!(heal_target(10.0, 2.0), 12.0);
        assert_eq!(heal_target(10.0, 5.0), 15.0);
        assert_eq!(heal_target(10.0, 0.0), 10.0);
        assert_eq!(heal_target(10.0, -3.0), 10.0);
        assert_eq!(heal_target(10.0, f32::NAN), 10.0);
        assert_eq!(heal_target(10.0, f32::INFINITY), 10.0);
    }
}

// ---------------------------------------------------------------------------
// Slice 2 — the powder chain: growth powder and mutating powder.
//
// The rules below are upstream's `MutatingPowderItem`/`MutagenRecipe` (the
// three `mutations/*` subclasses) and `GrowthPowderItem`, with no world access:
// `lib.rs` reads the level and the player and hands the values in. They are
// appended to slice 1's file, so `runtime.rs` is no longer byte-identical to
// the retired 0.1.0 bundle's copy (the migration's proof, not a running rule).

/// `RootsUtil.getRayTrace(level, player, 4)`: the mutating powder's reach.
pub const POWDER_REACH: u32 = 4;

/// The powder's ray moves this far per sample; ten samples make a block.
pub const RAY_STEP: f64 = 0.1;

/// `MutatingPowderItem`'s item-entity box: `pos ± 2` blocks on every axis.
pub const MUTATION_BOX: f64 = 2.0;

/// The herb one mutation makes and the vanilla flower it grows from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mutation {
    /// Blue orchid, a blaze rod and a lava bucket, in the Nether, ringed by netherrack.
    FlareOrchid,
    /// A poppy and a coal block, in The End, above obsidian, under Slowness.
    MidnightBloom,
    /// An oxeye daisy, glowstone and prismarine crystals, at noon, under Night Vision.
    RadiantDaisy,
}

impl Mutation {
    /// `MutagenManager.reload`'s order, which is the order the recipes are tried.
    pub const ALL: [Self; 3] = [Self::MidnightBloom, Self::FlareOrchid, Self::RadiantDaisy];

    /// The vanilla block the flower must be (`MutagenRecipe.plantBlock`).
    #[must_use]
    pub fn base(self) -> &'static str {
        match self {
            Self::FlareOrchid => "minecraft:blue_orchid",
            Self::MidnightBloom => "minecraft:poppy",
            Self::RadiantDaisy => "minecraft:oxeye_daisy",
        }
    }

    /// The herb the block becomes (`MutagenRecipe.result`).
    #[must_use]
    pub fn result(self) -> &'static str {
        match self {
            Self::FlareOrchid => "rootsclassic:flare_orchid",
            Self::MidnightBloom => "rootsclassic:midnight_bloom",
            Self::RadiantDaisy => "rootsclassic:radiant_daisy",
        }
    }

    /// The item entities the box must hold and nothing else (`addIngredient`).
    #[must_use]
    pub fn ingredients(self) -> &'static [&'static str] {
        match self {
            Self::FlareOrchid => &["minecraft:blaze_rod", "minecraft:lava_bucket"],
            Self::MidnightBloom => &["minecraft:coal_block"],
            Self::RadiantDaisy => &["minecraft:glowstone", "minecraft:prismarine_crystals"],
        }
    }
}

/// Everything `MutagenRecipe.matches` reads, as values: the block the powder's
/// ray landed on, where it is, what the player carries and what lies around it.
#[derive(Debug, Clone, Copy)]
pub struct MutagenScene<'a> {
    /// The id of the block the ray landed on (`level.getBlockState(pos)`).
    pub base: &'a str,
    /// The dimension's id (`level.dimension()`).
    pub dimension: &'a str,
    /// `level.getDayTime()`.
    pub day_time: i64,
    /// The block two below `base`.
    pub below2: &'a str,
    /// The eight horizontal neighbours, in the order
    /// `east, west, north, south, east+north, west+south, north+west, south+east`.
    pub neighbours: [&'a str; 8],
    /// The item ids of the item entities in the box, one entry per entity.
    pub items: &'a [&'a str],
    /// The ids of the effects the player carries.
    pub effects: &'a [&'a str],
}

/// The mutation this scene satisfies, tried in `MutagenManager.reload`'s order.
///
/// The box's stacks must be **exactly** the recipe's inputs: upstream removes
/// each required stack once and refuses the recipe when anything is left, so a
/// bystander drop in the box stops the mutation.
#[must_use]
pub fn mutation(scene: &MutagenScene<'_>) -> Option<Mutation> {
    Mutation::ALL
        .into_iter()
        .find(|recipe| matches(scene, *recipe))
}

/// One recipe against one scene: the base flower, exactly its ingredients, and
/// that recipe's own extra conditions.
fn matches(scene: &MutagenScene<'_>, recipe: Mutation) -> bool {
    if scene.base != recipe.base() || !exact_items(recipe.ingredients(), scene.items) {
        return false;
    }
    let has = |effect: &str| scene.effects.contains(&effect);
    match recipe {
        Mutation::FlareOrchid => {
            scene.dimension == "minecraft:the_nether"
                && has("minecraft:fire_resistance")
                && scene
                    .neighbours
                    .iter()
                    .all(|neighbour| *neighbour == "minecraft:netherrack")
        }
        Mutation::MidnightBloom => {
            scene.dimension == "minecraft:the_end"
                && scene.below2 == "minecraft:obsidian"
                && has("minecraft:slowness")
        }
        Mutation::RadiantDaisy => {
            scene.dimension == "minecraft:overworld"
                && has("minecraft:night_vision")
                && scene.day_time > 5000
                && scene.day_time < 7000
        }
    }
}

/// `MutagenRecipe.matches`'s item test: every wanted stack removes one found
/// stack by item, and nothing may be left over. Counts do not matter, as
/// `ItemStack.isSameItem` ignores them.
fn exact_items(wanted: &[&str], found: &[&str]) -> bool {
    if wanted.len() != found.len() {
        return false;
    }
    let mut pool = found.to_vec();
    for item in wanted {
        let Some(index) = pool.iter().position(|candidate| candidate == item) else {
            return false;
        };
        pool.swap_remove(index);
    }
    pool.is_empty()
}

/// What `GrowthPowderItem.applyGrowthHere` does to a block, before it asks
/// whether the block can be bone-mealed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Growth {
    /// Dirt becomes a grass block.
    Grass,
    /// Water with air above grows a lily pad above it.
    LilyPad,
}

/// The growth powder's special cases: dirt, and water with air above.
///
/// Anything else is left to the bone-meal attempt, which refuses a block that
/// cannot grow and is the success signal the powder is consumed on.
#[must_use]
pub fn growth(block: &str, above: &str) -> Option<Growth> {
    match block {
        "minecraft:dirt" => Some(Growth::Grass),
        "minecraft:water" if above == "minecraft:air" => Some(Growth::LilyPad),
        _ => None,
    }
}

/// The block positions `RootsUtil.getRayTrace` tests: `reach * 10` samples of
/// `RAY_STEP` from the eye along `look`, as block positions (`BlockPos.containing`
/// floors each coordinate).
pub fn ray_steps(eye: [f64; 3], look: [f64; 3], reach: u32) -> impl Iterator<Item = [i32; 3]> {
    (1..=reach.saturating_mul(10)).map(move |step| {
        let travelled = RAY_STEP * f64::from(step);
        [
            (eye[0] + look[0] * travelled).floor() as i32,
            (eye[1] + look[1] * travelled).floor() as i32,
            (eye[2] + look[2] * travelled).floor() as i32,
        ]
    })
}

#[cfg(test)]
mod powder_tests {
    use super::*;

    const NETHERRACK: [&str; 8] = ["minecraft:netherrack"; 8];

    fn flare<'a>(items: &'a [&'a str], effects: &'a [&'a str]) -> MutagenScene<'a> {
        MutagenScene {
            base: "minecraft:blue_orchid",
            dimension: "minecraft:the_nether",
            day_time: 18_000,
            below2: "minecraft:dirt",
            neighbours: NETHERRACK,
            items,
            effects,
        }
    }

    fn bloom<'a>(below2: &'a str, dimension: &'a str, effects: &'a [&'a str]) -> MutagenScene<'a> {
        MutagenScene {
            base: "minecraft:poppy",
            dimension,
            below2,
            ..flare(&["minecraft:coal_block"], effects)
        }
    }

    fn daisy<'a>(day_time: i64, effects: &'a [&'a str]) -> MutagenScene<'a> {
        const ITEMS: [&str; 2] = ["minecraft:glowstone", "minecraft:prismarine_crystals"];
        MutagenScene {
            base: "minecraft:oxeye_daisy",
            dimension: "minecraft:overworld",
            day_time,
            ..flare(&ITEMS, effects)
        }
    }

    #[test]
    fn the_powder_ray_walks_ten_steps_a_block() {
        let eye = [0.5, 1.5, 0.5];
        let look = [1.0, 0.0, 0.0];
        let mut steps = ray_steps(eye, look, POWDER_REACH);
        assert_eq!(
            steps.next(),
            Some([0, 1, 0]),
            "the first sample is 0.1 away"
        );
        let fifth = ray_steps(eye, look, POWDER_REACH).nth(4);
        assert_eq!(fifth, Some([1, 1, 0]), "the fifth sample crosses into x+1");
        assert_eq!(ray_steps(eye, look, POWDER_REACH).last(), Some([4, 1, 0]));
        assert_eq!(ray_steps(eye, look, POWDER_REACH).count(), 40);
        assert_eq!(POWDER_REACH, 4);
    }

    #[test]
    fn the_flare_orchid_needs_the_nether_ring_and_fire_resistance() {
        let items = ["minecraft:blaze_rod", "minecraft:lava_bucket"];
        let effects = ["minecraft:fire_resistance"];
        assert_eq!(
            mutation(&flare(&items, &effects)),
            Some(Mutation::FlareOrchid)
        );
        let mut overworld = flare(&items, &effects);
        overworld.dimension = "minecraft:overworld";
        assert_eq!(mutation(&overworld), None, "not the Nether");
        let mut ring = flare(&items, &effects);
        ring.neighbours[5] = "minecraft:stone";
        assert_eq!(mutation(&ring), None, "one neighbour is not netherrack");
        assert_eq!(
            mutation(&flare(&items, &[])),
            None,
            "without fire resistance"
        );
    }

    #[test]
    fn the_midnight_bloom_needs_obsidian_two_below_and_slowness() {
        let effects = ["minecraft:slowness"];
        assert_eq!(
            mutation(&bloom("minecraft:obsidian", "minecraft:the_end", &effects)),
            Some(Mutation::MidnightBloom)
        );
        assert_eq!(
            mutation(&bloom("minecraft:stone", "minecraft:the_end", &effects)),
            None,
            "the second block below must be obsidian"
        );
        assert_eq!(
            mutation(&bloom(
                "minecraft:obsidian",
                "minecraft:overworld",
                &effects
            )),
            None,
            "not The End"
        );
        assert_eq!(
            mutation(&bloom("minecraft:obsidian", "minecraft:the_end", &[])),
            None,
            "without slowness"
        );
    }

    #[test]
    fn the_radiant_daisy_needs_noon_and_night_vision() {
        let effects = ["minecraft:night_vision"];
        assert_eq!(
            mutation(&daisy(6000, &effects)),
            Some(Mutation::RadiantDaisy)
        );
        // Upstream's `> 5000 && < 7000`, both ends exclusive.
        for day in [5000, 4999, 7000, 7001] {
            assert_eq!(mutation(&daisy(day, &effects)), None, "day time {day}");
        }
        assert!(mutation(&daisy(6001, &effects)).is_some());
        assert_eq!(mutation(&daisy(6000, &[])), None, "without night vision");
    }

    #[test]
    fn the_items_must_be_exactly_the_recipe() {
        let effects = ["minecraft:fire_resistance"];
        let exact = ["minecraft:blaze_rod", "minecraft:lava_bucket"];
        assert!(mutation(&flare(&exact, &effects)).is_some());
        let extra = [
            "minecraft:blaze_rod",
            "minecraft:lava_bucket",
            "minecraft:stick",
        ];
        assert_eq!(
            mutation(&flare(&extra, &effects)),
            None,
            "a bystander stack stops the mutation, as upstream's exact match does"
        );
        let duplicate = ["minecraft:blaze_rod", "minecraft:blaze_rod"];
        assert_eq!(mutation(&flare(&duplicate, &effects)), None);
        assert_eq!(
            mutation(&flare(&[], &effects)),
            None,
            "no items, no mutation"
        );
        assert_eq!(mutation(&flare(&["minecraft:lava_bucket"], &effects)), None);
    }

    #[test]
    fn the_wrong_flower_never_mutates() {
        let items = ["minecraft:blaze_rod", "minecraft:lava_bucket"];
        let effects = ["minecraft:fire_resistance"];
        let mut dandelion = flare(&items, &effects);
        dandelion.base = "minecraft:dandelion";
        assert_eq!(mutation(&dandelion), None);
        let mut poppy = flare(&items, &effects);
        poppy.base = "minecraft:poppy";
        assert_eq!(mutation(&poppy), None, "a poppy is not the flare base");
    }

    #[test]
    fn growth_powder_knows_dirt_and_water() {
        assert_eq!(
            growth("minecraft:dirt", "minecraft:air"),
            Some(Growth::Grass)
        );
        assert_eq!(
            growth("minecraft:water", "minecraft:air"),
            Some(Growth::LilyPad)
        );
        assert_eq!(
            growth("minecraft:water", "minecraft:stone"),
            None,
            "a covered water block grows nothing"
        );
        assert_eq!(growth("minecraft:stone", "minecraft:air"), None);
        assert_eq!(growth("minecraft:grass_block", "minecraft:air"), None);
    }
}
