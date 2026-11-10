// Runs at the head of `Game::native_loot_drops` (API 75): the jar's global
// loot modifier adds one herb to the drops of a foraged block.
fn observe_loot_drops(
    game: &mut crate::game::Game<'_>,
    context: &crate::game::native_hooks::NativeLootDrops<'_>,
    drops: &mut Vec<horizon_client::items::ItemStack>,
) {
    crate::game::rootsclassic_state::on_loot_drops(game, context, drops);
}
