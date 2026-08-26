use core::dict::Felt252Dict;
use starknet::ContractAddress;
use caps::models::game::{Game, Action, ActionType};
use caps::models::cap::{Cap, CapTrait, CapType, TargetType, TargetTypeTrait, Location};
use caps::models::effect::{Effect, EffectTrait, EffectType, Timing};
use caps::logic::helpers::{
    handle_start_of_turn_effects, check_includes, clone_dicts, handle_damage,
};

pub fn process_actions(
    ref game: Game,
    ref turn: Array<Action>,
    ref locations: Felt252Dict<u64>,
    ref keys: Felt252Dict<Nullable<Cap>>,
    ref start_of_turn_effects: Array<Effect>,
    ref move_step_effects: Array<Effect>,
    ref end_of_turn_effects: Array<Effect>,
    caller: ContractAddress,
) -> (
    Game, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>, Array<Effect>, Array<Effect>, Array<Effect>,
) {
    //handle start of turn effects
    let (extra_energy, stunned_pieces, mut new_start_of_turn_effects) =
        handle_start_of_turn_effects(
        @start_of_turn_effects,
    );

    let mut energy: u8 = match game.turn_count {
        0 => 0,
        1 => 2, // p1 first turn
        2 => 2, // p2 first turn
        3 => 5, // p1 second turn
        4 => 5, // p2 second turn
        _ => 7, // third turn and beyond
    };

    let mut i = 0;
    while i < turn.len() {
        let action = turn.at(i);
        let mut cap = keys.get((*action.cap_id).into()).deref();
        assert!(cap.owner == caller.into(), "You are not the owner of this piece");
        assert!(!check_includes(@stunned_pieces, cap.id), "Piece is stunned");
        let cap_type: CapType = caps::sets::set_zero::get_cap_type(cap.cap_type).unwrap();
        let mut new_effects: Array<Effect> = ArrayTrait::new();
        let mut new_move_step_effects: Array<Effect> = ArrayTrait::new();

        match action.action_type {
            ActionType::Move(dir) => {
                let mut move_discount: u8 = 0;
                let mut move_bonus: u8 = 0;
                for mut effect in move_step_effects {
                    match effect.effect_type {
                        EffectType::MoveDiscount(x) => {
                            move_discount += x;
                            effect.trigger();
                            if effect.remaining_triggers > 0 {
                                new_move_step_effects.append(effect);
                            }
                        },
                        EffectType::MoveBonus(x) => {
                            move_bonus += x;
                            effect.trigger();
                            if effect.remaining_triggers > 0 {
                                new_move_step_effects.append(effect);
                            }
                        },
                        _ => { new_move_step_effects.append(effect); },
                    }
                };
                move_step_effects = new_move_step_effects;
                let mut move_cost = cap_type.move_cost;
                if move_discount > cap_type.move_cost {
                    move_cost = 0;
                } else {
                    move_cost -= move_discount;
                }
                assert!(
                    move_cost <= energy,
                    "Not enough energy, move cost: {}, energy: {}",
                    move_cost,
                    energy,
                );
                energy -= move_cost;
                let new_location_index = cap.get_new_index_from_dir(*dir.x, *dir.y);
                let piece_at_location_id = locations.get(new_location_index.into());
                assert!(cap.get_position().is_some(), "Cap is not on the board");
                let cap_position = cap.get_position().unwrap();
                assert!(
                    piece_at_location_id == 0,
                    "There is a piece at the new location, id: {}",
                    piece_at_location_id,
                );
                let old_position_index = cap_position.x * 7 + cap_position.y;
                locations.insert(old_position_index.into(), 0);
                cap.move(cap_type, *dir.x, *dir.y, move_bonus);
                locations.insert((cap_position.x * 7 + cap_position.y).into(), cap.id);
                keys.insert(cap.id.into(), NullableTrait::new(cap));
            },
            ActionType::Attack(target) => {
                let mut attack_cost = cap_type.attack_cost;
                let mut attack_discount: u8 = 0;
                let mut attack_bonus: u8 = 0;

                for mut effect in move_step_effects {
                    match effect.effect_type {
                        EffectType::AttackDiscount(x) => {
                            attack_discount += x;
                            effect.trigger();
                            if effect.remaining_triggers > 0 {
                                new_move_step_effects.append(effect);
                            }
                        },
                        EffectType::AttackBonus(x) => {
                            attack_bonus += x;
                            effect.trigger();
                            if effect.remaining_triggers > 0 {
                                new_move_step_effects.append(effect);
                            }
                        },
                        _ => { new_move_step_effects.append(effect); },
                    }
                };
                move_step_effects = new_move_step_effects;
                if attack_discount > cap_type.attack_cost {
                    attack_cost = 0;
                } else {
                    attack_cost -= attack_discount;
                }

                assert!(
                    attack_cost <= energy,
                    "Not enough energy, attack cost: {}, energy: {}",
                    attack_cost,
                    energy,
                );
                energy -= attack_cost;
                let mut attack_dmg = cap_type.attack_dmg;
                attack_dmg += attack_bonus.into();

                let piece_at_location_id = locations.get((*target.x * 7 + *target.y).into());
                let mut piece_at_location: Cap = keys.get(piece_at_location_id.into()).deref();
                assert!(piece_at_location_id != 0, "There is no piece at the target location");
                assert!(
                    piece_at_location.owner != caller.into(), "You cannot attack your own piece",
                );
                assert!(cap.check_in_range(*target, @cap_type.attack_range), "Attack is not valid");
                let (new_game, new_cap) = handle_damage(
                    ref game, ref piece_at_location, attack_dmg.try_into().unwrap(),
                );
                game = new_game;
                keys.insert(new_cap.id.into(), NullableTrait::new(new_cap));
            },
            ActionType::Ability(target) => {
                let mut cap_type: CapType = caps::sets::set_zero::get_cap_type(cap.cap_type)
                    .unwrap();
                assert!(cap_type.ability_target != TargetType::None, "Ability should not be none");
                let (valid, new_game, new_locations, new_keys) = cap_type
                    .ability_target
                    .is_valid(@cap, ref cap_type, *target, ref game, ref locations, ref keys);
                game = new_game;
                keys = new_keys;
                locations = new_locations;
                assert!(valid, "Ability is not valid");
                let mut ability_cost = cap_type.ability_cost;
                let mut ability_discount = 0;
                let mut double_count: u8 = 0;

                for mut effect in move_step_effects {
                    match effect.effect_type {
                        EffectType::AbilityDiscount(x) => {
                            ability_discount += x;
                            effect.trigger();
                            if effect.remaining_triggers > 0 {
                                new_move_step_effects.append(effect);
                            }
                        },
                        EffectType::Double(x) => {
                            double_count += x;
                            effect.trigger();
                            if effect.remaining_triggers > 0 {
                                new_move_step_effects.append(effect);
                            }
                        },
                        _ => { new_move_step_effects.append(effect); },
                    }
                };
                move_step_effects = new_move_step_effects;
                if ability_discount > cap_type.ability_cost {
                    ability_cost = 0;
                } else {
                    ability_cost -= ability_discount;
                }

                assert!(
                    ability_cost <= energy,
                    "Not enough energy, ability cost: {}, energy: {}",
                    ability_cost,
                    energy,
                );
                energy -= ability_cost;

                let mut cap_type_for_use = caps::sets::set_zero::get_cap_type(cap.cap_type)
                    .unwrap();
                let (mut new_game, mut created_effects, new_caps) =
                    caps::sets::set_zero::use_ability(
                    ref cap, ref cap_type_for_use, *target, ref game, ref locations, ref keys,
                );
                game = new_game;
                let (new_locations, new_keys) = caps::logic::helpers::get_dicts_from_array(
                    @new_caps,
                );
                locations = new_locations;
                keys = new_keys;

                for effect in created_effects {
                    new_effects.append(effect);
                };

                while double_count > 0 {
                    let mut cap_type_for_double = caps::sets::set_zero::get_cap_type(
                        cap.cap_type,
                    )
                        .unwrap();
                    let (valid, new_game, new_locations, new_keys) = cap_type_for_double
                        .ability_target
                        .is_valid(@cap, ref cap_type_for_double, *target, ref game, ref locations, ref keys);
                    game = new_game;
                    locations = new_locations;
                    keys = new_keys;
                    if valid {
                        let mut cap_type_for_double2 = caps::sets::set_zero::get_cap_type(
                            cap.cap_type,
                        )
                            .unwrap();
                        let (mut new_game, new_double_effects, new_caps) =
                            caps::sets::set_zero::use_ability(
                            ref cap, ref cap_type_for_double2, *target, ref game, ref locations, ref keys,
                        );
                        let (new_locations, new_keys) =
                            caps::logic::helpers::get_dicts_from_array(
                            @new_caps,
                        );
                        locations = new_locations;
                        keys = new_keys;
                        for effect in new_double_effects {
                            new_effects.append(effect);
                        };
                        double_count -= 1;
                        game = new_game;
                    } else {
                        double_count = 0;
                    }
                }
            },
            ActionType::Play(location) => {
                let mut cap = keys.get((cap.id).into()).deref();
                let cap_type: CapType = caps::sets::set_zero::get_cap_type(cap.cap_type)
                    .unwrap();
                assert!(cap.owner == caller.into(), "You are not the owner of this piece");
                assert!(cap.location == Location::Bench, "Piece is not on the bench");
                assert!(
                    cap_type.play_cost <= energy,
                    "Not enough energy, play cost: {}, energy: {}",
                    cap_type.play_cost,
                    energy,
                );
                energy -= cap_type.play_cost;
                //todo check if location is valid (is there a piece there? and is it the last row?)
                cap.location = Location::Board(*location);
                keys.insert(cap.id.into(), NullableTrait::new(cap));
                locations.insert((*location.x * 7 + *location.y).into(), cap.id);
            },
        };

        for effect in new_effects {
            match effect.get_timing() {
                Timing::StartOfTurn => { new_start_of_turn_effects.append(effect); },
                Timing::MoveStep => { move_step_effects.append(effect); },
                Timing::EndOfTurn => { end_of_turn_effects.append(effect); },
                _ => {},
            }
        };

        let (new_game, new_locations, new_keys) = clone_dicts(@game, ref locations, ref keys);
        game = new_game;
        keys = new_keys;
        locations = new_locations;
        i += 1;
    };

    let (new_game, new_locations, new_keys) = clone_dicts(@game, ref locations, ref keys);

    (
        new_game,
        new_locations,
        new_keys,
        new_start_of_turn_effects,
        move_step_effects.clone(),
        end_of_turn_effects.clone(),
    )
}
