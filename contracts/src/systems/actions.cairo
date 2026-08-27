use caps::models::game::{Game, Action, Vec2, Global};
use caps::models::cap::{Cap, Location};
use caps::logic::track::{
    is_walkable, get_p1_deploy_spot, get_p2_deploy_spot, is_valid_step,
    LAYOUT_PERIMETER_5X5,
};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IActions<T> {
    fn create_game(ref self: T, p2: ContractAddress) -> u64;
    fn create_game_with_layout(ref self: T, p2: ContractAddress, layout: u8) -> u64;
    fn create_solo_game(ref self: T) -> u64;
    fn create_solo_game_with_layout(ref self: T, layout: u8) -> u64;
    fn take_turn(ref self: T, game_id: u64, turn: Array<Action>);
    fn get_game(self: @T, game_id: u64) -> Option<(Game, Span<Cap>)>;
}

/// Position helpers (no world access needed).
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

fn index_of_id(caps: @Array<Cap>, id: u64) -> usize {
    let mut i: usize = 0;
    while i < caps.len() {
        if (*caps.at(i)).id == id {
            return i;
        }
        i += 1;
    };
    caps.len()
}

fn has_cap_at(caps: @Array<Cap>, pos: Vec2) -> bool {
    index_at(caps, pos) < caps.len()
}

#[dojo::contract]
pub mod actions {
    use super::{
        IActions, index_at, index_of_id, has_cap_at, is_walkable,
        get_p1_deploy_spot, get_p2_deploy_spot, is_valid_step,
        LAYOUT_PERIMETER_5X5,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use caps::models::game::{Game, Global, Action, Vec2, ActionType};
    use caps::models::cap::{
        Cap, Location, cap_stats, dist, get_position,
    };
    use dojo::model::ModelStorage;

    pub const TEAM_SIZE: u8 = 6;

    /// Re-reads every cap referenced by the game from the world.
    fn alive_caps(world: @dojo::world::WorldStorage, game: @Game) -> Array<Cap> {
        let mut caps = ArrayTrait::new();
        let mut i: usize = 0;
        while i < game.caps_ids.len() {
            let cap: Cap = world.read_model(*game.caps_ids[i]);
            caps.append(cap);
            i += 1;
        };
        caps
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn create_game(ref self: ContractState, p2: ContractAddress) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p2, LAYOUT_PERIMETER_5X5)
        }

        fn create_game_with_layout(ref self: ContractState, p2: ContractAddress, layout: u8) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p2, layout)
        }

        fn create_solo_game(ref self: ContractState) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p1, LAYOUT_PERIMETER_5X5)
        }

        fn create_solo_game_with_layout(ref self: ContractState, layout: u8) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p1, layout)
        }

        fn take_turn(ref self: ContractState, game_id: u64, turn: Array<Action>) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);

            assert!(!game.over, "Game is over");

            let caller: felt252 = get_caller_address().into();
            let turn_player: felt252 = if game.turn_count % 2 == 0 {
                game.player1
            } else {
                game.player2
            };
            assert!(caller == turn_player, "Not your turn");

            let layout = game.layout;

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
                        assert!(is_walkable(layout, pos), "Tile is not on layout");
                        assert!(cap.location == Location::Bench, "Not on bench");
                        assert!(!has_cap_at(@caps, pos), "Tile is occupied");

                        let deploy_pos = if cap.owner == game.player1 {
                            get_p1_deploy_spot(layout)
                        } else {
                            get_p2_deploy_spot(layout)
                        };
                        assert!(pos.x == deploy_pos.x && pos.y == deploy_pos.y,
                            "Must play at your deploy spot");
                        cap.location = Location::Board(pos);
                        world.write_model(@cap);
                    },
                    ActionType::Move(pos) => {
                        assert!(is_walkable(layout, pos), "Tile is not on layout");
                        assert!(cap.location != Location::Bench, "Not on board");
                        let cur = get_position(@cap).unwrap();
                        assert!(is_walkable(layout, cur), "Current pos not on layout");
                        assert!(!has_cap_at(@caps, pos), "Tile is occupied");

                        assert!(
                            is_valid_step(layout, cur, pos),
                            "Must move 1 step (orthogonal or diagonal) along layout",
                        );
                        cap.location = Location::Board(pos);
                        world.write_model(@cap);
                    },
                    ActionType::Attack(pos) => {
                        assert!(is_walkable(layout, pos), "Target tile not on layout");
                        let (_, atk, attack_range, _) = cap_stats(cap.cap_type);
                        assert!(cap.location != Location::Bench, "Not on board");
                        let cur = get_position(@cap).unwrap();
                        assert!(dist(cur, pos) <= attack_range.into(), "Attack out of range");
                        let tgt_idx = index_at(@caps, pos);
                        assert!(tgt_idx < caps.len(), "No target on tile");
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

            let mut p1_alive = false;
            let mut p2_alive = false;
            let mut p1_tower = false;
            let mut p2_tower = false;
            let mut new_ids: Array<u64> = ArrayTrait::new();
            let mut j: usize = 0;
            while j < game.caps_ids.len() {
                let cap_id = *game.caps_ids[j];
                let cap: Cap = world.read_model(cap_id);
                match cap.location {
                    Location::Dead => {},
                    _ => {
                        new_ids.append(cap_id);
                        if cap.owner == game.player1 {
                            p1_alive = true;
                            if cap.cap_type == 0 { p1_tower = true; }
                        } else if cap.owner == game.player2 {
                            p2_alive = true;
                            if cap.cap_type == 0 { p2_tower = true; }
                        }
                    },
                }
                j += 1;
            };
            game.caps_ids = new_ids;

            if !p1_tower || !p1_alive {
                game.over = true;
                game.winner = game.player2;
            } else if !p2_tower || !p2_alive {
                game.over = true;
                game.winner = game.player1;
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
            let mut caps: Array<Cap> = ArrayTrait::new();
            let mut i: usize = 0;
            while i < game.caps_ids.len() {
                caps.append(world.read_model(*game.caps_ids[i]));
                i += 1;
            };
            Option::Some((game, caps.span()))
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _create_game(
            ref self: ContractState,
            p1: ContractAddress,
            p2: ContractAddress,
            layout: u8,
        ) -> u64 {
            let mut world = self.world_default();
            let mut global: Global = world.read_model(0);

            let game_id = global.games_counter + 1;
            global.games_counter = game_id;

            let p1_felt: felt252 = p1.into();
            let p2_felt: felt252 = p2.into();

            let mut game = Game {
                id: game_id,
                player1: p1_felt,
                player2: p2_felt,
                layout: layout,
                turn_count: 0,
                over: false,
                winner: 0,
                caps_ids: ArrayTrait::new(),
                last_action_timestamp: 0,
            };

            let mut cap_counter = global.cap_counter;

            let mut i: u8 = 0;
            while i < TEAM_SIZE {
                let cap_type: u8 = if i == 0 { 0 } else { i };
                let (hp, _, _, _) = cap_stats(cap_type);

                cap_counter += 1;
                let cap1 = Cap {
                    id: cap_counter,
                    owner: p1_felt,
                    cap_type: cap_type,
                    location: Location::Bench,
                    health: hp,
                };
                world.write_model(@cap1);
                game.caps_ids.append(cap1.id);

                cap_counter += 1;
                let cap2 = Cap {
                    id: cap_counter,
                    owner: p2_felt,
                    cap_type: cap_type,
                    location: Location::Bench,
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

        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"caps")
        }
    }
}
