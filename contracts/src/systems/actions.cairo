use caps::models::game::{Game, Action};
use caps::models::cap::{Cap, CapType};
use caps::models::effect::{Effect};
use starknet::ContractAddress;
// define the interface
#[starknet::interface]
pub trait IActions<T> {
    fn create_game(
        ref self: T, p1: ContractAddress, p2: ContractAddress, p1_team: u16, p2_team: u16,
    ) -> u64;
    fn take_turn(ref self: T, game_id: u64, turn: Array<Action>);
    fn get_game(self: @T, game_id: u64) -> Option<(Game, Span<Cap>, Span<Effect>)>;
    fn get_cap_data(self: @T, set_id: u64, cap_type: u16) -> Option<CapType>;
    fn simulate_turn(
        self: @T, game: Game, caps: Array<Cap>, effects: Option<Array<Effect>>, turn: Array<Action>,
    ) -> (Game, Span<Effect>, Span<Cap>);
}


// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{IActions};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use caps::models::game::{Vec2, Game, Global, GameTrait, Action};
    use caps::models::effect::{Effect};
    use caps::models::cap::{Cap, CapType, Location};
    use caps::models::set::{ISetInterfaceDispatcher, ISetInterfaceDispatcherTrait, Set};
    use caps::helpers::{
        get_piece_locations, get_active_effects, update_end_of_turn_effects,
        get_dicts_from_array, process_actions, get_active_effects_from_array,
    };
    use core::dict::{Felt252DictTrait};

    use dojo::model::{ModelStorage};
    use dojo::event::EventStorage;

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct Moved {
        #[key]
        pub player: ContractAddress,
        #[key]
        pub game_id: u64,
        #[key]
        pub turn_number: u64,
        pub turn: Span<Action>,
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn create_game(
            ref self: ContractState,
            p1: ContractAddress,
            p2: ContractAddress,
            p1_team: u16,
            p2_team: u16,
        ) -> u64 {
            // Get the default world.
            let mut world = self.world_default();

            let mut global: Global = world.read_model(0);

            let game_id = global.games_counter + 1;
            global.games_counter = game_id;
            world.write_model(@global);

            let mut game = Game {
                id: game_id,
                player1: p1.into(),
                player2: p2.into(),
                caps_ids: ArrayTrait::new(),
                turn_count: 0,
                over: false,
                effect_ids: ArrayTrait::new(),
                last_action_timestamp: get_block_timestamp(),
            };

            let p1_types = array![
                0 + p1_team, 4 + p1_team, 8 + p1_team, 12 + p1_team, 16 + p1_team, 20 + p1_team,
            ];
            let p2_types = array![
                0 + p2_team, 4 + p2_team, 8 + p2_team, 12 + p2_team, 16 + p2_team, 20 + p2_team,
            ];

            let p1_cap1 = Cap {
                id: global.cap_counter + 1,
                owner: p1.into(),
                location: Location::Board(Vec2 { x: 2, y: 0 }),
                set_id: 0,
                cap_type: *p1_types[0],
                dmg_taken: 0,
                shield_amt: 0,
            };
            let p1_cap2 = Cap {
                id: global.cap_counter + 2,
                owner: p1.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p1_types[1],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p1_cap3 = Cap {
                id: global.cap_counter + 3,
                owner: p1.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p1_types[2],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p1_cap4 = Cap {
                id: global.cap_counter + 4,
                owner: p1.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p1_types[3],
                dmg_taken: 0,
                shield_amt: 0,
            };
            let p1_cap5 = Cap {
                id: global.cap_counter + 5,
                owner: p1.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p1_types[4],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p1_cap6 = Cap {
                id: global.cap_counter + 6,
                owner: p1.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p1_types[5],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p2_cap1 = Cap {
                id: global.cap_counter + 7,
                owner: p2.into(),
                location: Location::Board(Vec2 { x: 2, y: 6 }),
                set_id: 0,
                cap_type: *p2_types[0],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p2_cap2 = Cap {
                id: global.cap_counter + 8,
                owner: p2.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p2_types[1],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p2_cap3 = Cap {
                id: global.cap_counter + 9,
                owner: p2.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p2_types[2],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p2_cap4 = Cap {
                id: global.cap_counter + 10,
                owner: p2.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p2_types[3],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p2_cap5 = Cap {
                id: global.cap_counter + 11,
                owner: p2.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p2_types[4],
                dmg_taken: 0,
                shield_amt: 0,
            };

            let p2_cap6 = Cap {
                id: global.cap_counter + 12,
                owner: p2.into(),
                location: Location::Bench,
                set_id: 0,
                cap_type: *p2_types[5],
                dmg_taken: 0,
                shield_amt: 0,
            };

            game.add_cap(p1_cap1.id);
            game.add_cap(p1_cap2.id);
            game.add_cap(p1_cap3.id);
            game.add_cap(p1_cap4.id);
            game.add_cap(p1_cap5.id);
            game.add_cap(p1_cap6.id);
            game.add_cap(p2_cap1.id);
            game.add_cap(p2_cap2.id);
            game.add_cap(p2_cap3.id);
            game.add_cap(p2_cap4.id);
            game.add_cap(p2_cap5.id);
            game.add_cap(p2_cap6.id);

            global.cap_counter = global.cap_counter + 12;

            world.write_model(@game);
            world.write_model(@p1_cap1);
            world.write_model(@p1_cap2);
            world.write_model(@p1_cap3);
            world.write_model(@p1_cap4);
            world.write_model(@p1_cap5);
            world.write_model(@p1_cap6);
            world.write_model(@p2_cap1);
            world.write_model(@p2_cap2);
            world.write_model(@p2_cap3);
            world.write_model(@p2_cap4);
            world.write_model(@p2_cap5);
            world.write_model(@p2_cap6);
            world.write_model(@global);

            game_id
        }

        fn take_turn(ref self: ContractState, game_id: u64, turn: Array<Action>) {
            let mut world = self.world_default();

            let mut turn = turn;

            let clone = turn.clone();
            let mut game: Game = world.read_model(game_id);

            let (over, _) = @game.check_over(@world);
            if *over {
                if !game.over {
                    game.over = true;
                    world.write_model(@game);
                    return;
                }
                panic!("Game is over");
            }

            if game.turn_count % 2 == 0 {
                assert!(
                    //temp to test without changing controllers constantly
                    get_caller_address() == game.player1, "You are not the turn player, 1s turn",
                );
            } else if game.turn_count % 2 == 1 {
                assert!(
                    get_caller_address() == game.player2, "You are not the turn player, 2s turn",
                );
            } 

            let (mut start_of_turn_effects, mut move_step_effects, mut end_of_turn_effects) =
                get_active_effects(
                ref game, @world,
            );

            let (mut locations, mut keys) = get_piece_locations(ref game, @world);

            let caller = get_caller_address();

            let (
                new_game,
                new_locations,
                new_keys,
                new_start_of_turn_effects,
                new_move_step_effects,
                new_end_of_turn_effects,
            ) =
                process_actions(
                ref game,
                ref turn,
                locations,
                ref keys,
                ref start_of_turn_effects,
                ref move_step_effects,
                ref end_of_turn_effects,
                caller,
            );
            game = new_game;
            locations = new_locations;
            keys = new_keys;
            move_step_effects = new_move_step_effects;
            end_of_turn_effects = new_end_of_turn_effects;

            let (mut game, mut new_end_of_turn_effects, new_locations, new_keys) =
                update_end_of_turn_effects(
                ref game, ref end_of_turn_effects, locations, keys,
            );
            end_of_turn_effects = new_end_of_turn_effects;
            locations = new_locations;
            keys = new_keys;

            let mut i = 0;
            while i < game.caps_ids.len() {
                let cap_id = *game.caps_ids[i];
                let cap = keys.get(cap_id.into()).deref();
                let cap_type = self.get_cap_data(cap.set_id, cap.cap_type).unwrap();
                if cap.dmg_taken >= cap_type.base_health {
                    game.remove_cap(cap_id);
                    world.erase_model(@cap);
                } else {
                    world.write_model(@cap);
                }
                i += 1;
            };

            let mut new_effect_ids: Array<u64> = ArrayTrait::new();
            for effect in new_start_of_turn_effects {
                if effect.remaining_triggers > 0 {
                    new_effect_ids.append(effect.effect_id);
                    world.write_model(@effect);
                }
            };
            for effect in move_step_effects {
                if effect.remaining_triggers > 0 {
                    new_effect_ids.append(effect.effect_id);
                    world.write_model(@effect);
                }
            };
            for effect in end_of_turn_effects {
                if effect.remaining_triggers > 0 {
                    new_effect_ids.append(effect.effect_id);
                    world.write_model(@effect);
                }
            };

            game.last_action_timestamp = get_block_timestamp();
            game.turn_count = game.turn_count + 1;
            game.effect_ids = new_effect_ids;
            let (over, _) = @game.check_over(@world);
            game.over = *over;
            world.write_model(@game);

            world
                .emit_event(
                    @Moved {
                        player: get_caller_address(),
                        game_id: game_id,
                        turn_number: game.turn_count - 1,
                        turn: clone.span(),
                    },
                );
        }

        fn simulate_turn(
            self: @ContractState,
            game: Game,
            caps: Array<Cap>,
            effects: Option<Array<Effect>>,
            turn: Array<Action>,
        ) -> (Game, Span<Effect>, Span<Cap>) {
            //the only world read is for the set. This is just for convenience and shouldn't be too
            //hard to remove when neccesary we still need to figure out how to handle the sets when
            //running in wasm anyways
            let mut world = self.world(@"caps");
            let mut effects = effects.unwrap_or(ArrayTrait::new());
            let mut game = game;
            let mut turn = turn;

            let (mut start_of_turn_effects, mut move_step_effects, mut end_of_turn_effects) =
                get_active_effects_from_array(
                @game, @effects,
            );

            let mut caller = 0.try_into().unwrap();

            if game.turn_count % 2 == 0 {
                caller = game.player1;
            } else {
                caller = game.player2;
            }

            let (mut locations, mut keys) = get_dicts_from_array(@caps);

            let (
                new_game,
                new_locations,
                new_keys,
                new_start_of_turn_effects,
                new_move_step_effects,
                new_end_of_turn_effects,
            ) =
                process_actions(
                ref game,
                ref turn,
                locations,
                ref keys,
                ref start_of_turn_effects,
                ref move_step_effects,
                ref end_of_turn_effects,
                caller,
            );

            game = new_game;
            locations = new_locations;
            keys = new_keys;
            move_step_effects = new_move_step_effects;
            end_of_turn_effects = new_end_of_turn_effects;

            let (mut game, mut new_end_of_turn_effects, new_locations, new_keys) =
                update_end_of_turn_effects(
                ref game, ref end_of_turn_effects, locations, keys,
            );

            end_of_turn_effects = new_end_of_turn_effects;
            locations = new_locations;
            keys = new_keys;

            let mut final_caps: Array<Cap> = ArrayTrait::new();
            let mut i = 0;
            let mut one_found = false;
            let mut two_found = false;
            let mut one_tower_found = false;
            let mut two_tower_found = false;
            while i < game.caps_ids.len() {
                let cap_id = *game.caps_ids[i];
                let cap = keys.get(cap_id.into()).deref();
                let cap_type = self.get_cap_data(cap.set_id, cap.cap_type).unwrap();
                if cap.dmg_taken >= cap_type.base_health {
                    game.remove_cap(cap_id);
                } else {
                    if cap.owner == (game.player1).into() {
                        //todo: better way to tell if it's a tower
                        if cap.cap_type < 4 {
                            one_tower_found = true;
                        }
                        one_found = true;
                    } else if cap.owner == (game.player2).into() {
                        if cap.cap_type < 4 {
                            two_tower_found = true;
                        }
                        two_found = true;
                    }
                    final_caps.append(cap);
                }
                i += 1;
            };

            if !one_found || !one_tower_found {
                game.over = true;
            }
            if !two_found || !two_tower_found {
                game.over = true;
            }
            let mut final_effects: Array<Effect> = ArrayTrait::new();
            let mut new_effect_ids: Array<u64> = ArrayTrait::new();
            for effect in new_start_of_turn_effects {
                if effect.remaining_triggers > 0 {
                    new_effect_ids.append(effect.effect_id);
                    final_effects.append(effect);
                }
            };
            for effect in move_step_effects {
                if effect.remaining_triggers > 0 {
                    new_effect_ids.append(effect.effect_id);
                    final_effects.append(effect);
                }
            };
            for effect in end_of_turn_effects {
                if effect.remaining_triggers > 0 {
                    new_effect_ids.append(effect.effect_id);
                    final_effects.append(effect);
                }
            };

            game.last_action_timestamp = get_block_timestamp();
            game.turn_count = game.turn_count + 1;
            game.effect_ids = new_effect_ids;

            (game, final_effects.span(), final_caps.span())
        }

        fn get_game(self: @ContractState, game_id: u64) -> Option<(Game, Span<Cap>, Span<Effect>)> {
            let mut world = self.world_default();
            let game: Game = world.read_model(game_id);
            if game.player1 == 0.try_into().unwrap() {
                return Option::None;
            }
            let mut i = 0;
            let mut caps: Array<Cap> = ArrayTrait::new();
            while i < game.caps_ids.len() {
                let cap: Cap = world.read_model(*game.caps_ids[i]);
                caps.append(cap);
                i += 1;
            };

            let mut i: u64 = 0;
            let mut effects: Array<Effect> = ArrayTrait::new();
            while i < game.effect_ids.len().into() {
                let effect: Effect = world.read_model((game_id, i));
                if effect.remaining_triggers > 0 {
                    effects.append(effect);
                }
                i += 1;
            };
            Option::Some((game, caps.span(), effects.span()))
        }

        fn get_cap_data(self: @ContractState, set_id: u64, cap_type: u16) -> Option<CapType> {
            let mut world = self.world_default();
            let set: Set = world.read_model(set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };
            dispatcher.get_cap_type(cap_type)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Use the default namespace "dojo_starter". This function is handy since the ByteArray
        /// can't be const.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"caps")
        }
    }
}
