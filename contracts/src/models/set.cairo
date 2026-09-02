use caps::models::game::Vec2;
use caps::models::set_data::{CapType, AbilityContext, SetOutput};
use starknet::ContractAddress;

/// The extensibility boundary between the core game and piece sets.
///
/// A "set" is a standalone contract that defines pieces (stats via
/// `get_cap_type`) and their abilities (via `activate_ability`). Anyone
/// can deploy a set; a game references one set contract and plays with
/// those pieces under the same core rules.
///
/// Set contracts are PURE FUNCTIONS: they receive a snapshot of relevant
/// state and return `SetOp`s (state-mutation intents) that the core
/// validates and applies. Sets never receive world access or mutable
/// state. See docs/SET_OPS.md.
#[starknet::interface]
pub trait ISetInterface<T> {
    /// Piece definitions. Returns stats + ability metadata for the set's
    /// piece type `id`, or None if the set doesn't define it.
    fn get_cap_type(self: @T, id: u16) -> Option<CapType>;

    /// Execute the ability of `ctx.actor` at `target` (already validated
    /// by the core against the CapType's ability_target/ability_range).
    /// Returns the ops to apply + client events.
    fn activate_ability(self: @T, ctx: AbilityContext, target: Vec2) -> SetOutput;
}

/// Registered set contract reference. `games` reference a set by id.
#[derive(Drop, Copy, Serde, Introspect)]
#[dojo::model]
pub struct Set {
    #[key]
    pub id: u64,
    pub address: ContractAddress,
    // ── budgets (see docs/SET_OPS.md §4) ──
    /// Max pieces of this set that may exist on the board at once.
    pub max_on_board: u8,
    /// Max distinct cap types this set may define.
    pub max_cap_types: u16,
    /// Hard cap on ops per ability activation.
    pub max_ops_per_ability: u8,
}
