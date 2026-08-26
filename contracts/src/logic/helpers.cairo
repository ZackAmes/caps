use core::dict::Felt252Dict;
use caps::models::game::{Game, GameTrait};
use caps::models::cap::{Cap, CapTrait};
use caps::models::effect::{Effect, EffectTrait, EffectType, EffectTarget, Timing};

pub fn check_includes(array: @Array<u64>, id: u64) -> bool {
    let mut i = 0;
    let mut found = false;
    while i < array.len() {
        if *array.at(i) == id {
            found = true;
            break;
        }
        i += 1;
    };
    return found;
}

pub fn clone_dicts(
    game: @Game, ref locations: Felt252Dict<u64>, ref keys: Felt252Dict<Nullable<Cap>>,
) -> (Game, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    let mut new_locations: Felt252Dict<u64> = Default::default();
    let mut new_keys: Felt252Dict<Nullable<Cap>> = Default::default();

    let mut i = 0;
    while i < game.caps_ids.len() {
        let cap: Cap = keys.get((*game.caps_ids[i]).into()).deref();
        let position = cap.get_position();
        if position.is_none() {
            new_keys.insert(cap.id.into(), NullableTrait::new(cap));
            i += 1;
            continue;
        }
        let position = position.unwrap();
        let index = position.x * 7 + position.y;
        new_locations.insert(index.into(), cap.id);
        new_keys.insert(cap.id.into(), NullableTrait::new(cap));
        i += 1;
    };

    (game.clone(), new_locations, new_keys)
}

pub fn get_dicts_from_array(caps: @Array<Cap>) -> (Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    let mut locations: Felt252Dict<u64> = Default::default();
    let mut keys: Felt252Dict<Nullable<Cap>> = Default::default();

    let mut i = 0;
    while i < caps.len() {
        let cap: Cap = *caps.at(i);
        let position = cap.get_position();
        if position.is_none() {
            keys.insert(cap.id.into(), NullableTrait::new(cap));
            i += 1;
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

pub fn get_active_effects_from_array(
    game: @Game, effects: @Array<Effect>,
) -> (Array<Effect>, Array<Effect>, Array<Effect>) {
    let mut start_of_turn_effects: Array<Effect> = ArrayTrait::new();
    let mut move_step_effects: Array<Effect> = ArrayTrait::new();
    let mut end_of_turn_effects: Array<Effect> = ArrayTrait::new();

    let mut i = 0;
    while i < effects.len() {
        let effect = *effects.at(i);
        match effect.get_timing() {
            Timing::StartOfTurn => { start_of_turn_effects.append(effect); },
            Timing::MoveStep => { move_step_effects.append(effect); },
            Timing::EndOfTurn => { end_of_turn_effects.append(effect); },
            _ => {},
        }
        i += 1;
    };

    (start_of_turn_effects, move_step_effects, end_of_turn_effects)
}

// Returns (extra_energy, stunned_pieces, new_effects)
pub fn handle_start_of_turn_effects(
    start_of_turn_effects: @Array<Effect>,
) -> (u8, Array<u64>, Array<Effect>) {
    let mut i = 0;
    let mut extra_energy: u8 = 0;
    let mut stunned_pieces: Array<u64> = ArrayTrait::new();
    let mut new_effects: Array<Effect> = ArrayTrait::new();
    while i < start_of_turn_effects.len() {
        let mut effect = *start_of_turn_effects.at(i);
        effect.trigger();
        if effect.remaining_triggers > 0 {
            new_effects.append(effect);
        }
        match effect.effect_type {
            EffectType::ExtraEnergy(x) => { extra_energy += x; },
            EffectType::Stun(x) => { stunned_pieces.append(x.into()); },
            _ => {},
        }
        i += 1;
    };
    (extra_energy, stunned_pieces, new_effects)
}

pub fn update_end_of_turn_effects(
    ref game: Game,
    ref end_of_turn_effects: Array<Effect>,
    ref locations: Felt252Dict<u64>,
    ref keys: Felt252Dict<Nullable<Cap>>,
) -> (Game, Array<Effect>, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
    let mut i = 0;
    let mut new_effects: Array<Effect> = ArrayTrait::new();
    while i < end_of_turn_effects.len() {
        let mut effect = *end_of_turn_effects.at(i);
        effect.trigger();
        if effect.remaining_triggers > 0 {
            new_effects.append(effect);
        }
        match effect.effect_type {
            EffectType::DOT(dmg) => {
                if let EffectTarget::Cap(cap_id) = effect.target {
                        let mut cap: Cap = keys.get(cap_id.into()).deref();
                        let (new_game, new_cap) = handle_damage(
                            ref game, ref cap, dmg.into(),
                        );
                        game = new_game;
                        keys.insert(cap_id.into(), NullableTrait::new(new_cap));
                }
            },
            EffectType::Heal(heal) => {
                if let EffectTarget::Cap(cap_id) = effect.target {
                    let mut cap: Cap = keys.get(cap_id.into()).deref();
                    if heal.into() > cap.dmg_taken {
                        cap.dmg_taken = 0;
                    } else {
                        cap.dmg_taken -= heal.into();
                    }
                    keys.insert(cap_id.into(), NullableTrait::new(cap));
                }
            },
            _ => {},
        };
        i += 1;
    };
    let (new_game, new_locations, new_keys) = clone_dicts(@game, ref locations, ref keys);
    (new_game, new_effects, new_locations, new_keys)
}

pub fn handle_damage(
    ref game: Game, ref target: Cap, amount: u64,
) -> (Game, Cap) {
    let cap_type = caps::sets::set_zero::get_cap_type(target.cap_type).unwrap();

    let remaining_health = cap_type.base_health - target.dmg_taken;

    if target.shield_amt.into() > amount {
        target.shield_amt -= amount.try_into().unwrap();
    } else if amount > target.shield_amt.into() + remaining_health.into() {
        target.dmg_taken = cap_type.base_health;
        target.shield_amt = 0;
        game.remove_cap(target.id.try_into().unwrap());
    } else {
        target.dmg_taken += (amount - target.shield_amt.try_into().unwrap()).try_into().unwrap();
        target.shield_amt = 0;
    }

    return (game.clone(), target);
}
