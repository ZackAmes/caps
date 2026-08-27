use caps::models::game::{Game, Action, Vec2};
use caps::models::cap::{Cap, Location};
use starknet::ContractAddress;
use dojo::world::WorldStorage;
use dojo::model::ModelStorage;

#[starknet::interface]
pub trait IActions<T> {
    /// Creates a new game. The caller is player1; `p2` is the opponent.
    fn create_game(ref self: T, p2: ContractAddress) -> u64;
    /// Submit a list of actions for the current turn player.
    fn take_turn(ref self: T, game_id: u64, turn: Array<Action>);
    /// Fetch the game plus its live caps.
    fn get_game(self: @T, game_id: u64) -> Option<(Game, Span<Cap>)>;
}

/// Re-reads every cap referenced by the game from the world.
fn alive_caps(world: @WorldStorage, game: @Game) -> Array<Cap> {
    let mut caps = ArrayTrait::new();
    let mut i: usize = 0;
    while i < game.caps_ids.len() {
        let cap: Cap = world.read_model(*game.caps_ids[i]);
        caps.append(cap);
        i += 1;
    };
    caps
}

/// Returns the index (into `caps`) of a non-dead cap at `pos`, or `caps.len()` if empty.
fn index_at(caps: @Array<Cap>, pos: Vec2) -> usize {
    let mut i: usize = 0;
    while i < caps.len() {
        let cap: Cap = *caps.at(i);
        match cap.location {
            Location::Board(v) => { if v.x == pos.x && v.y == pos.y { return i; } },
            _ => {},
        }
        i += 1;
    };
    caps.len()
}

/// Returns the index of the cap with `id`, or `len()` if not found.
fn index_of_id(caps: @Array<Cap>, id: u64) -> usize {
    let mut i: usize = 0;
    while i < caps.len() {
        let cap: Cap = *caps.at(i);
        if cap.id == id {
            return i;
        }
        i += 1;
    };
    caps.len()
}

#[dojo::contract]
pub mod actions {
    use super::{IActions, alive_caps, index_at, index_of_id};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use caps::models::game::{Game, Global, Action, Vec2, ActionType};
    use caps::models::cap::{
        Cap, Location, cap_stats, dist, in_bounds, get_position, BOARD_Y,
    };
    use dojo::model::ModelStorage;

    pub const TEAM_SIZE: u8 = 6;

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn create_game(ref self: ContractState, p2: ContractAddress) -> u64 {
            let mut world = self.world_default();
            let mut global: Global = world.read_model(0);

            let game_id = global.games_counter + 1;
            global.games_counter = game_id;

            let p1: felt252 = get_caller_address().into();
            let p2: felt252 = p2.into();

            let mut game = Game {
                id: game_id,
                player1: p1,
                player2: p2,
                turn_count: 0,
                over: false,
                winner: 0,
                caps_ids: ArrayTrait::new(),
                last_action_timestamp: 0,
            };

            let mut cap_counter = global.cap_counter;
            let p1_home: u8 = 0;
            let p2_home: u8 = BOARD_Y - 1;

            let mut i: u8 = 0;
            while i < TEAM_SIZE {
                let cap_type: u8 = if i == 0 {
                    0
                } else if i == 1 {
                    1
                } else if i == 2 {
                    2
                } else if i == 3 {
                    3
                } else {
                    1
                };
                let (hp, _, _, _) = cap_stats(cap_type);

                // p1 cap
                cap_counter += 1;
                let p1_loc = if i == 0 { Location::Board(Vec2 { x: 1, y: p1_home }) } else {
                    Location::Bench
                };
                let cap1 = Cap {
                    id: cap_counter,
                    owner: p1,
                    cap_type: cap_type,
                    location: p1_loc,
                    health: hp,
                };
                world.write_model(@cap1);
                game.caps_ids.append(cap1.id);

                // p2 cap
                cap_counter += 1;
                let p2_loc = if i == 0 { Location::Board(Vec2 { x: 1, y: p2_home }) } else {
                    Location::Bench
                };
                let cap2 = Cap {
                    id: cap_counter,
                    owner: p2,
                    cap_type: cap_type,
                    location: p2_loc,
                    health: hp,
                };
                world.write_model(@cap2);
                game.caps_ids.append(cap2.id);

                i += 1;
            };

            global.cap_counter = cap_counter;
            world.write_model(@game);
            world.write_model(@global);

            game_id
        }

        fn take_turn(ref self: ContractState, game_id: u64, turn: Array<Action>) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);

            if game.over {
                panic!("Game is over");
            }

            let caller: felt252 = get_caller_address().into();
            let turn_player: felt252 = if game.turn_count % 2 == 0 {
                game.player1
            } else {
                game.player2
            };
            assert!(caller == turn_player, "Not your turn");

            let mut i: usize = 0;
            while i < turn.len() {
                let action: Action = *turn.at(i);

                let caps = alive_caps(@world, @game);
                let act_idx = index_of_id(@caps, action.cap_id);
                assert!(act_idx < caps.len(), "Cap not found");
                let mut cap: Cap = *caps.at(act_idx);
                assert!(cap.owner == caller, "Not your cap");
                assert!(cap.location != Location::Dead, "Cap is dead");

                match action.action_type {
                    ActionType::Play(pos) => {
                        assert!(in_bounds(pos), "Out of bounds");
                        assert!(cap.location == Location::Bench, "Not on bench");
                        assert!(index_at(@caps, pos) == caps.len(), "Cell occupied");
                        cap.location = Location::Board(pos);
                        world.write_model(@cap);
                    },
                    ActionType::Move(pos) => {
                        assert!(in_bounds(pos), "Out of bounds");
                        let (_, _, _, move_range) = cap_stats(cap.cap_type);
                        assert!(cap.location != Location::Bench, "Not on board");
                        let cur = get_position(@cap).unwrap();
                        assert!(index_at(@caps, pos) == caps.len(), "Cell occupied");
                        let d = dist(cur, pos);
                        assert!(
                            d >= 1 && d <= move_range.into(), "Move out of range:",
                        );
                        cap.location = Location::Board(pos);
                        world.write_model(@cap);
                    },
                    ActionType::Attack(pos) => {
                        assert!(in_bounds(pos), "Out of bounds");
                        let (_, atk, attack_range, _) = cap_stats(cap.cap_type);
                        assert!(cap.location != Location::Bench, "Not on board");
                        let cur = get_position(@cap).unwrap();
                        assert!(dist(cur, pos) <= attack_range.into(), "Attack out of range");
                        let tgt_idx = index_at(@caps, pos);
                        assert!(tgt_idx < caps.len(), "No target there");
                        let mut target: Cap = *caps.at(tgt_idx);
                        assert!(target.id != cap.id, "Cannot attack self");
                        assert!(target.owner != caller, "Cannot attack your own cap");
                        let dmg: u16 = atk;
                        if target.health > dmg {
                            target.health -= dmg;
                        } else {
                            target.health = 0;
                        }
                        if target.health == 0 {
                            target.location = Location::Dead;
                        }
                        world.write_model(@target);
                    },
                }

                i += 1;
            };

            // Prune dead caps and resolve the winner.
            let mut dead_count: Array<u64> = ArrayTrait::new();
            let mut p1_alive = false;
            let mut p2_alive = false;
            let mut new_ids: Array<u64> = ArrayTrait::new();
            let mut j: usize = 0;
            while j < game.caps_ids.len() {
                let cap_id = *game.caps_ids[j];
                let cap: Cap = world.read_model(cap_id);
                match cap.location {
                    Location::Dead => { dead_count.append(cap_id); },
                    _ => {
                        new_ids.append(cap_id);
                        if cap.owner == game.player1 {
                            p1_alive = true;
                        } else if cap.owner == game.player2 {
                            p2_alive = true;
                        }
                    },
                }
                j += 1;
            };
            game.caps_ids = new_ids;

            if p1_alive && !p2_alive {
                game.over = true;
                game.winner = game.player1;
            } else if p2_alive && !p1_alive {
                game.over = true;
                game.winner = game.player2;
            } else if !p1_alive && !p2_alive {
                game.over = true;
                game.winner = 0;
            }

            game.last_action_timestamp = get_block_timestamp();
            game.turn_count += 1;
            world.write_model(@game);
        }

        fn get_game(self: @ContractState, game_id: u64) -> Option<(Game, Span<Cap>)> {
            let world = self.world_default();
            let game: Game = world.read_model(game_id);
            if game.player1 == 0 {
                return Option::None;
            }
            let mut i: usize = 0;
            let mut caps: Array<Cap> = ArrayTrait::new();
            while i < game.caps_ids.len() {
                let cap: Cap = world.read_model(*game.caps_ids[i]);
                caps.append(cap);
                i += 1;
            };
            Option::Some((game, caps.span()))
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"caps")
        }
    }
}