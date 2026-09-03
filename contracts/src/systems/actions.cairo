use caps::models::game::{Game, Action, Vec2};
use caps::models::cap::{Cap, Location};
use caps::logic::track::{
    is_walkable, get_p1_deploy_spot, get_p2_deploy_spot, is_valid_step,
    get_walkable_neighbors, LAYOUT_PERIMETER_5X5,
};
use starknet::ContractAddress;

use caps::models::set_data::CapType;
use caps::models::game::Hand;

#[starknet::interface]
pub trait IActions<T> {
    /// Register a set contract (governance in production).
    fn register_set(
        ref self: T,
        address: ContractAddress,
        max_on_board: u8,
        max_cap_types: u16,
        max_ops_per_ability: u8,
    ) -> u64;
    fn create_game(ref self: T, p2: ContractAddress) -> u64;
    fn create_game_with_layout(ref self: T, p2: ContractAddress, layout: u8) -> u64;
    fn create_solo_game(ref self: T) -> u64;
    fn create_solo_game_with_layout(ref self: T, layout: u8) -> u64;
    fn take_turn(ref self: T, game_id: u64, turn: Array<Action>);
    fn get_game(self: @T, game_id: u64) -> Option<(Game, Span<Cap>)>;
    /// Fetch a piece definition from the game's set contract.
    fn get_cap_data(self: @T, game_id: u64, cap_type_id: u16) -> Option<CapType>;
    /// Fetch a player's hand (public — both hands visible).
    fn get_hand(self: @T, game_id: u64, player_slot: u8) -> Option<(Hand, Span<u64>)>;
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

/// True if the cap at `pos` is fully surrounded:
/// every walkable neighbor of `pos` is occupied by a cap belonging to the
/// opponent of the surrounded cap (unclaimed tiles, bench/dead caps, and friendly
/// caps don't count as blockers).
fn is_surrounded(caps: @Array<Cap>, layout: u8, pos: Vec2) -> bool {
    let idx = index_at(caps, pos);
    if idx >= caps.len() {
        return false;
    }
    let target: Cap = *caps.at(idx);
    if target.cap_type == 0 {
        // Towers cannot be captured by surrounding; they must be destroyed.
        return false;
    }

    let neighbors = get_walkable_neighbors(layout, pos);
    if neighbors.len() == 0 {
        return false;
    }

    let mut n: usize = 0;
    while n < neighbors.len() {
        let npos = *neighbors.at(n);
        let nidx = index_at(caps, npos);
        if nidx >= caps.len() {
            // Free escape tile exists -> not surrounded
            return false;
        }
        let blocker: Cap = *caps.at(nidx);
        if blocker.owner == target.owner {
            // A friendly cap adjacent does not block escape
            return false;
        }
        n += 1;
    };

    true
}

use caps::models::effect::{Effect, EffectTarget};
use caps::models::set_data::EffectSnapshot;

fn _effect_snapshots(effects: @Array<Effect>) -> Span<EffectSnapshot> {
    let mut snaps = ArrayTrait::new();
    let mut i: usize = 0;
    while i < effects.len() {
        let e: Effect = *effects.at(i);
        let cap_id = match e.target {
            EffectTarget::Cap(id) => id,
            _ => 0,
        };
        snaps.append(
            EffectSnapshot {
                effect_type: e.effect_type,
                target_cap_id: cap_id,
                remaining_triggers: e.remaining_triggers,
            },
        );
        i += 1;
    };
    snaps.span()
}

#[dojo::contract]
pub mod actions {
    use super::{
        IActions, index_at, index_of_id, has_cap_at, is_surrounded, is_walkable, _effect_snapshots,
        get_p1_deploy_spot, get_p2_deploy_spot, is_valid_step,
        LAYOUT_PERIMETER_5X5,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use caps::models::game::{Game, Global, Action, ActionType};
    use caps::models::cap::{Cap, Location, get_position};
    use caps::models::effect::{Effect, EffectTarget, Timing};
    use caps::models::set_data::EffectTickerTrait;
    use caps::models::set::{Set, ISetInterfaceDispatcher, ISetInterfaceDispatcherTrait};
    use caps::models::set_data::{CapType, TargetType, AbilityContext, ActorInfo, CapInfo, EffectSnapshot};
    use caps::logic::ops::apply_op;
    use caps::models::game::Hand;
    use caps::logic::hand::{is_in_hand, advance_cursor, HAND_SIZE};
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
            let set_id = game.set_id;

            // ── Energy economy (docs/GAME_DESIGN.md §3.4) ──
            let mut effects = self._load_effects(game_id, @game);

            // ── Start of turn: tick StartOfTurn effects ──
            // Applies ExtraEnergy + resolves Stuns, decrements triggers.
            let start_tick = EffectTickerTrait::tick_effects(
                @effects, Timing::StartOfTurn, game.turn_count,
            );
            effects = start_tick.effects;

            let mut energy: u8 = match game.turn_count {
                0 => 0,
                1 => 2,
                2 => 2,
                3 => 5,
                4 => 5,
                _ => 7,
            };
            energy += start_tick.extra_energy;
            game.energy = energy;

            let mut caps = alive_caps(@world, @game);

            let mut i: usize = 0;
            while i < turn.len() {
                let action: Action = *turn.at(i);
                let act_idx = index_of_id(@caps, action.cap_id);
                assert!(act_idx < caps.len(), "Cap not found");
                let mut cap: Cap = *caps.at(act_idx);
                assert!(cap.owner == caller, "Not your cap");
                assert!(cap.location != Location::Dead, "Cap is dead");

                // Stun check: skip action if this cap is stunned
                let mut si: usize = 0;
                let mut is_stunned = false;
                while si < start_tick.stunned.len() {
                    if *start_tick.stunned.at(si) == cap.id {
                        is_stunned = true;
                        break;
                    }
                    si += 1;
                };
                assert!(!is_stunned, "Cap is stunned");

                match action.action_type {
                    ActionType::Play(pos) => {
                        assert!(is_walkable(layout, pos), "Tile is not on layout");
                        assert!(cap.location == Location::Bench, "Not on bench");
                        assert!(!has_cap_at(@caps, pos), "Tile is occupied");

                        // Hand check: the piece must be in the player's
                        // current hand window.
                        let player_slot: u8 = if cap.owner == game.player1 { 0 } else { 1 };
                        let hand: Hand = world.read_model((game_id, player_slot));
                        assert!(is_in_hand(@hand, cap.id), "Piece is not in your hand");

                        let deploy_pos = if cap.owner == game.player1 {
                            get_p1_deploy_spot(layout)
                        } else {
                            get_p2_deploy_spot(layout)
                        };
                        assert!(pos.x == deploy_pos.x && pos.y == deploy_pos.y,
                            "Must play at your deploy spot");
                        let (_, play_cost, _, _) = self._stats(game.set_id, cap.cap_type);
                        assert!(energy >= play_cost, "Not enough energy to deploy");
                        energy -= play_cost;
                        cap.location = Location::Board(pos);
                        world.write_model(@cap);

                        // Advance the hand cursor — the cycle continues.
                        let mut hand_updated = hand;
                        advance_cursor(ref hand_updated);
                        world.write_model(@hand_updated);
                    },
                    ActionType::Move(pos) => {
                        assert!(is_walkable(layout, pos), "Tile is not on layout");
                        assert!(cap.location != Location::Bench, "Not on board");
                        let cur = get_position(@cap).unwrap();
                        assert!(is_walkable(layout, cur), "Current pos not on layout");

                        assert!(
                            is_valid_step(layout, cur, pos),
                            "Must move 1 step (orthogonal or diagonal) along layout",
                        );

                        let (_, _, move_cost, _) = self._stats(game.set_id, cap.cap_type);
                        assert!(energy >= move_cost, "Not enough energy to move");
                        energy -= move_cost;

                        let tgt_idx = index_at(@caps, pos);
                        if tgt_idx < caps.len() {
                            // Moving onto an enemy attacks it. If it dies the
                            // mover takes the tile; otherwise the mover stays.
                            let mut target: Cap = *caps.at(tgt_idx);
                            assert!(target.id != cap.id, "Cannot attack self");
                            assert!(target.owner != caller, "Tile is occupied by your own cap");
                            let (_, _, _, atk) = self._stats(game.set_id, cap.cap_type);
                            if target.shield >= atk {
                                target.shield -= atk;
                            } else {
                                let through = atk - target.shield;
                                target.shield = 0;
                                if target.health > through {
                                    target.health -= through;
                                } else {
                                    target.health = 0;
                                    target.location = Location::Dead;
                                    cap.location = Location::Board(pos);
                                }
                            }
                            world.write_model(@target);
                        } else {
                            cap.location = Location::Board(pos);
                        }
                        world.write_model(@cap);
                    },
                    ActionType::Ability(pos) => {
                        // Fetch the piece definition from the set contract
                        let set: Set = world.read_model(game.set_id);
                        let dispatcher = ISetInterfaceDispatcher {
                            contract_address: set.address,
                        };
                        let cap_type: CapType = dispatcher
                            .get_cap_type(cap.cap_type)
                            .expect('Unknown cap type');

                        // Energy charge
                        assert!(energy >= cap_type.ability_cost, "Not enough energy");
                        energy -= cap_type.ability_cost;

                        // Target validation (declarative, from CapType)
                        let actor_pos_v = get_position(@cap).unwrap();
                        let mut in_range = false;
                        let mut ri: usize = 0;
                        while ri < cap_type.ability_range.len() {
                            let off = *cap_type.ability_range.at(ri);
                            if actor_pos_v.x == pos.x + off.x
                                && actor_pos_v.y == pos.y + off.y {
                                in_range = true;
                                break;
                            }
                            ri += 1;
                        };
                        assert!(in_range, "Target out of ability range");

                        let tgt_idx = index_at(@caps, pos);
                        match cap_type.ability_target {
                            TargetType::None => panic!("No ability"),
                            TargetType::SelfCap => {},
                            TargetType::TeamCap => {
                                assert!(tgt_idx < caps.len(), "No cap at target");
                                let t: Cap = *caps.at(tgt_idx);
                                assert!(t.owner == caller, "Target is not friendly");
                            },
                            TargetType::OpponentCap => {
                                assert!(tgt_idx < caps.len(), "No cap at target");
                                let t: Cap = *caps.at(tgt_idx);
                                assert!(t.owner != caller, "Target is not an enemy");
                            },
                            TargetType::AnyCap => {
                                assert!(tgt_idx < caps.len(), "No cap at target");
                            },
                            TargetType::AnySquare => {},
                        }

                        // Build the ability context snapshot
                        let mut cap_infos = ArrayTrait::new();
                        let mut bi: usize = 0;
                        while bi < caps.len() {
                            let c: Cap = *caps.at(bi);
                            let pos_v = get_position(@c);
                            if pos_v.is_some() {
                                let p = pos_v.unwrap();
                                cap_infos.append(
                                    CapInfo {
                                        id: c.id,
                                        owner: c.owner,
                                        cap_type: c.cap_type,
                                        x: p.x,
                                        y: p.y,
                                        health: c.health,
                                    },
                                );
                            }
                            bi += 1;
                        };
                        let actor_pos_v = get_position(@cap).unwrap();
                        let ctx = AbilityContext {
                            game_id: game.id,
                            layout: game.layout,
                            turn_count: game.turn_count,
                            energy,
                            actor: ActorInfo {
                                id: cap.id,
                                owner: cap.owner,
                                cap_type: cap.cap_type,
                                x: actor_pos_v.x,
                                y: actor_pos_v.y,
                                health: cap.health,
                            },
                            caps: cap_infos.span(),
                            effects: _effect_snapshots(@effects),
                        };

                        // Dispatch to the set contract — pure function returning ops
                        let output = dispatcher.activate_ability(ctx, pos);

                        // Apply ops sequentially, bounded by the set's budget
                        let mut next_effect_id: u64 = (game.effect_ids.len() + 1000)
                            .try_into()
                            .unwrap();
                        let mut count: u8 = 0;
                        let mut oi: usize = 0;
                        while oi < output.ops.len() {
                            if count >= set.max_ops_per_ability {
                                break;
                            }
                            let op = *output.ops.at(oi);
                            if apply_op(
                                ref caps, ref effects, cap.id, cap.owner, layout,
                                ref next_effect_id, op,
                            ) {
                                count += 1;
                            }
                            oi += 1;
                        };

                        // Persist mutated caps + new effects
                        let mut wi: usize = 0;
                        while wi < caps.len() {
                            let c = *caps.at(wi);
                            world.write_model(@c);
                            wi += 1;
                        };
                        let mut ei: usize = 0;
                        while ei < effects.len() {
                            let e = *effects.at(ei);
                            world.write_model(@e);
                            game.effect_ids.append(e.effect_id);
                            ei += 1;
                        };
                    },
                    ActionType::ClaimCapture(pos) => {
                        assert!(cap.location != Location::Bench, "Not on board");
                        let tgt_idx = index_at(@caps, pos);
                        assert!(tgt_idx < caps.len(), "No target on tile");
                        let mut target: Cap = *caps.at(tgt_idx);
                        assert!(target.owner != caller, "Cannot capture your own cap");

                        assert!(
                            is_surrounded(@caps, layout, pos),
                            "Target is not surrounded",
                        );

                        // Send the surrounded cap back to bench with full health.
                        target.location = Location::Bench;
                        let (max_hp, _, _, _) = self._stats(game.set_id, target.cap_type);
                        target.health = max_hp;
                        target.shield = 0;
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

            game.energy = energy;

            // ── End of turn: tick EndOfTurn effects (DOT, Heal) ──
            let end_tick = EffectTickerTrait::tick_effects(
                @effects, Timing::EndOfTurn, game.turn_count,
            );

            // Apply DOT damage (needs cap stats for death handling)
            let mut di: usize = 0;
            while di < end_tick.dot_damage.len() {
                let hit = *end_tick.dot_damage.at(di);
                let cap_idx = index_of_id(@caps, hit.cap_id);
                if cap_idx < caps.len() {
                    let mut target: Cap = *caps.at(cap_idx);
                    if target.location != Location::Dead {
                        if target.shield >= hit.amount {
                            target.shield -= hit.amount;
                        } else {
                            let through = hit.amount - target.shield;
                            target.shield = 0;
                            if target.health > through {
                                target.health -= through;
                            } else {
                                target.health = 0;
                                target.location = Location::Dead;
                            }
                        }
                        world.write_model(@target);
                    }
                }
                di += 1;
            };

            // Apply Heal effects
            let mut hi: usize = 0;
            while hi < end_tick.heal_amounts.len() {
                let hit = *end_tick.heal_amounts.at(hi);
                let cap_idx = index_of_id(@caps, hit.cap_id.into());
                if cap_idx < caps.len() {
                    let mut target: Cap = *caps.at(cap_idx);
                    if target.location != Location::Dead {
                        // Heal clamps at cap type max (fetch from set)
                        let max_hp: u16 = self._stats_max_health(game.set_id, target.cap_type);
                        if target.health < max_hp {
                            if target.health + hit.amount > max_hp {
                                target.health = max_hp;
                            } else {
                                target.health += hit.amount;
                            }
                        }
                        world.write_model(@target);
                    }
                }
                hi += 1;
            };

            // Persist surviving effects
            self._write_effects(@game, end_tick.effects);

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

        fn register_set(
            ref self: ContractState,
            address: ContractAddress,
            max_on_board: u8,
            max_cap_types: u16,
            max_ops_per_ability: u8,
        ) -> u64 {
            let mut world = self.world_default();
            let mut global: Global = world.read_model(0);
            let set_id = global.sets_counter;
            global.sets_counter = set_id + 1;
            world.write_model(@global);
            let set = Set {
                id: set_id,
                address,
                max_on_board,
                max_cap_types,
                max_ops_per_ability,
            };
            world.write_model(@set);
            set_id
        }

        fn get_cap_data(
            self: @ContractState, game_id: u64, cap_type_id: u16,
        ) -> Option<CapType> {
            let world = self.world_default();
            let game: Game = world.read_model(game_id);
            let set: Set = world.read_model(game.set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };
            dispatcher.get_cap_type(cap_type_id)
        }

        fn get_hand(
            self: @ContractState, game_id: u64, player_slot: u8,
        ) -> Option<(Hand, Span<u64>)> {
            let world = self.world_default();
            let hand: Hand = world.read_model((game_id, player_slot));
            if hand.roster.len() == 0 {
                return Option::None;
            }
            // window ids as span for the client
            let window = caps::logic::hand::window_ids(@hand);
            Option::Some((hand, window.span()))
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
                set_id: 0,
                turn_count: 0,
                over: false,
                winner: 0,
                caps_ids: ArrayTrait::new(),
                effect_ids: ArrayTrait::new(),
                energy: 0,
                last_action_timestamp: 0,
            };

            let mut cap_counter = global.cap_counter;

            let mut i: u8 = 0;
            while i < TEAM_SIZE {
                let cap_type: u16 = if i == 0 { 0 } else { i.into() };
                let (hp, _, _, _) = self._stats(game.set_id, cap_type);

                cap_counter += 1;
                let cap1 = Cap {
                    id: cap_counter,
                    owner: p1_felt,
                    cap_type,
                    set_id: game.set_id,
                    location: Location::Bench,
                    health: hp,
                    shield: 0,
                    stunned_turns: 0,
                };
                world.write_model(@cap1);
                game.caps_ids.append(cap1.id);

                cap_counter += 1;
                let cap2 = Cap {
                    id: cap_counter,
                    owner: p2_felt,
                    cap_type,
                    set_id: game.set_id,
                    location: Location::Bench,
                    health: hp,
                    shield: 0,
                    stunned_turns: 0,
                };
                world.write_model(@cap2);
                game.caps_ids.append(cap2.id);

                i += 1;
            };

            global.cap_counter = cap_counter;

            // ── Hands: even-indexed caps are P1's roster, odd are P2's.
            // Roster order = creation order; the cycle is deterministic.
            let mut p1_roster = ArrayTrait::new();
            let mut p2_roster = ArrayTrait::new();
            let mut hi: usize = 0;
            while hi < game.caps_ids.len() {
                if hi % 2 == 0 {
                    p1_roster.append(*game.caps_ids.at(hi));
                } else {
                    p2_roster.append(*game.caps_ids.at(hi));
                }
                hi += 1;
            };
            let hand1 = Hand {
                game_id,
                player_slot: 0,
                roster: p1_roster,
                cursor: 0,
                hand_size: HAND_SIZE,
            };
            let hand2 = Hand {
                game_id,
                player_slot: 1,
                roster: p2_roster,
                cursor: 0,
                hand_size: HAND_SIZE,
            };
            world.write_model(@hand1);
            world.write_model(@hand2);

            world.write_model(@game);
            world.write_model(@global);

            game_id
        }

        /// Fetch stats from the game's set contract. Falls back to v1
        /// stats if the set doesn't define the type (never happens for
        /// registered sets, but keeps the compiler happy).
        fn _stats(
            ref self: ContractState, set_id: u64, cap_type: u16,
        ) -> (u16, u8, u8, u16) {
            let world = self.world_default();
            let set: Set = world.read_model(set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };
            match dispatcher.get_cap_type(cap_type) {
                Option::Some(ct) => (ct.max_health, ct.play_cost, ct.move_cost, ct.attack),
                Option::None => (8, 1, 1, 2),
            }
        }

        fn _load_effects(
            ref self: ContractState, game_id: u64, game: @Game,
        ) -> Array<Effect> {
            let world = self.world_default();
            let mut effects = ArrayTrait::new();
            let mut i: usize = 0;
            while i < game.effect_ids.len() {
                let e: Effect = world.read_model((game_id, *game.effect_ids[i]));
                if e.remaining_triggers > 0 {
                    effects.append(e);
                }
                i += 1;
            };
            effects
        }

        fn _write_effects(ref self: ContractState, game: @Game, effects: Array<Effect>) {
            let mut world = self.world_default();
            let mut i: usize = 0;
            while i < effects.len() {
                let e = *effects.at(i);
                if e.remaining_triggers > 0 {
                    world.write_model(@e);
                } else {
                    world.erase_model(@e);
                }
                i += 1;
            };
        }

        fn _stats_attack(ref self: ContractState, set_id: u64, cap_type: u16) -> u16 {
            2
        }

        fn _stats_max_health(ref self: ContractState, set_id: u64, cap_type: u16) -> u16 {
            8
        }

        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"caps")
        }
    }
}