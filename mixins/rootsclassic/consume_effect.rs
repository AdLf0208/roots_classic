// Runs at the head of `Game::native_consume_effect` (API 74): a consumable's
// effect kind of the mod's own, `rootsclassic:heal`, heals the acting player.
fn observe_consume_effect(
    game: &mut crate::game::Game<'_>,
    kind: &str,
    data: &serde_json::Value,
) {
    crate::game::rootsclassic_state::on_consume_effect(game, kind, data);
}
