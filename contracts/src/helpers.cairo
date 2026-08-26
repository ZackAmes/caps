use dojo::model::{ModelStorage};
use caps::models::game::{Game, Action};
use caps::models::cap::{Cap, CapTrait};
use caps::models::effect::{Effect, EffectTrait, Timing};
use starknet::ContractAddress;
use dojo::world::WorldStorage;
use core::dict::Felt252Dict;

pub fn get_player_pieces(
    game_id: u64, player: ContractAddress, world: @WorldStorage,
) -> Array<u64> {
    let mut game: Game = world.read_model(game_id);
    let mut pieces: Array<u64> = ArrayTrait::new();
    let mut i = 0;

    assert!(game.player1 == player || game.player2 == player, "Not in game");

    while i < game.caps_ids.len() {
        let cap: Cap = world.read_model(*game.caps_ids[i]);
        if cap.owner == player.into() {
            pieces.append(cap.id);
        }
        i += 1;
    };

    pieces
}

pub fn get_piece_locations(
    ref game: Game, world: @WorldStorage,
) -> (Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    let mut locations: Felt252Dict<u64> = Default::default();
    let mut keys: Felt252Dict<Nullable<Cap>> = Default::default();
    let mut i = 0;

    while i < game.caps_ids.len() {
        let cap: Cap = world.read_model(*game.caps_ids[i]);
        let position = cap.get_position();
        if position.is_none() {
            keys.insert(cap.id.into(), NullableTrait::new(cap));
            i+=1;
            continue;
        }
        let position = position.unwrap();
        let index = position.x * 7 + position.y;
        locations.insert(index.into(), cap.id);
        keys.insert(cap.id.into(), NullableTrait::new(cap));
        i += 1;
    };

    (locations, keys)
}

pub fn get_active_effects(
    ref game: Game, world: @WorldStorage,
) -> (Array<Effect>, Array<Effect>, Array<Effect>) {
    let mut start_of_turn_effects: Array<Effect> = ArrayTrait::new();
    let mut move_step_effects: Array<Effect> = ArrayTrait::new();
    let mut end_of_turn_effects: Array<Effect> = ArrayTrait::new();

    let mut i = 0;
    while i < game.effect_ids.len() {
        let effect: Effect = world.read_model((game.id, i));
        match effect.get_timing() {
            Timing::StartOfTurn => { start_of_turn_effects.append(effect); },
            Timing::MoveStep => { move_step_effects.append(effect); },
            Timing::EndOfTurn => { end_of_turn_effects.append(effect); },
        }
        i += 1;
    };

    (start_of_turn_effects, move_step_effects, end_of_turn_effects)
}

pub fn get_active_effects_from_array(
    game: @Game, effects: @Array<Effect>,
) -> (Array<Effect>, Array<Effect>, Array<Effect>) {
    caps::logic::helpers::get_active_effects_from_array(game, effects)
}

pub fn get_dicts_from_array(caps: @Array<Cap>) -> (Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    caps::logic::helpers::get_dicts_from_array(caps)
}

pub fn update_end_of_turn_effects(
    ref game: Game,
    ref end_of_turn_effects: Array<Effect>,
    mut locations: Felt252Dict<u64>,
    mut keys: Felt252Dict<Nullable<Cap>>,
) -> (Game, Array<Effect>, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    caps::logic::helpers::update_end_of_turn_effects(
        ref game, ref end_of_turn_effects, ref locations, ref keys,
    )
}

pub fn process_actions(
    ref game: Game,
    ref turn: Array<Action>,
    mut locations: Felt252Dict<u64>,
    ref keys: Felt252Dict<Nullable<Cap>>,
    ref start_of_turn_effects: Array<Effect>,
    ref move_step_effects: Array<Effect>,
    ref end_of_turn_effects: Array<Effect>,
    caller: ContractAddress,
) -> (
    Game, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>, Array<Effect>, Array<Effect>, Array<Effect>,
) {
    caps::logic::process::process_actions(
        ref game,
        ref turn,
        ref locations,
        ref keys,
        ref start_of_turn_effects,
        ref move_step_effects,
        ref end_of_turn_effects,
        caller,
    )
}

pub fn clone_dicts(
    game: @Game, ref locations: Felt252Dict<u64>, ref keys: Felt252Dict<Nullable<Cap>>,
) -> (Game, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    caps::logic::helpers::clone_dicts(game, ref locations, ref keys)
}

pub fn handle_damage(
    ref game: Game, ref cap: Cap, dmg: u64,
) -> (Game, Cap) {
    caps::logic::helpers::handle_damage(ref game, ref cap, dmg)
}

pub use caps::logic::helpers::check_includes;
