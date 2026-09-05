use caps::logic::track::{
    LAYOUT_PERIMETER_5X5, get_p1_deploy_spot, get_p2_deploy_spot, is_valid_step, is_walkable,
};
use caps::models::cap::{Cap, Location};
use caps::models::game::{Action, Game, Hand, Vec2};
use caps::models::set_data::CapType;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IActions<T> {
    fn rules_version(self: @T) -> u8;
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
            Location::Board(v) => { if v.x == pos.x && v.y == pos.y {
                return i;
            } },
            _ => {},
        }
        i += 1;
    }
    caps.len()
}

fn index_of_id(caps: @Array<Cap>, id: u64) -> usize {
    let mut i: usize = 0;
    while i < caps.len() {
        if (*caps.at(i)).id == id {
            return i;
        }
        i += 1;
    }
    caps.len()
}

fn has_cap_at(caps: @Array<Cap>, pos: Vec2) -> bool {
    index_at(caps, pos) < caps.len()
}
use caps::logic::rules::is_surrounded;
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
        snaps
            .append(
                EffectSnapshot {
                    effect_type: e.effect_type,
                    target_cap_id: cap_id,
                    remaining_triggers: e.remaining_triggers,
                },
            );
        i += 1;
    }
    snaps.span()
}

#[dojo::contract]
pub mod actions {
    use caps::logic::hand::{HAND_SIZE, is_in_hand, requeue};
    use caps::logic::ops::{apply_damage, apply_heal, apply_op};
    use caps::logic::rules::{
        BASE_INCOME, add_energy, capture_ready_turn, is_goal, objective_income, spend_action,
    };
    use caps::models::cap::{Cap, Location, get_position, is_on_board};
    use caps::models::effect::{Effect, EffectTarget, EffectTrait, EffectType, Passive, PassiveType};
    use caps::models::game::{Action, ActionType, Game, Global, Hand};
    use caps::models::set::{ISetInterfaceDispatcher, ISetInterfaceDispatcherTrait, Set};
    use caps::models::set_data::{
        AbilityContext, ActorInfo, CapInfo, CapType, SetOp, SetOpDamage, SetOpHeal, TargetType,
        apply_damage_reduction, conditional_attack_bonus,
    };
    use core::num::traits::Zero;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::{
        IActions, LAYOUT_PERIMETER_5X5, _effect_snapshots, get_p1_deploy_spot, get_p2_deploy_spot,
        has_cap_at, index_at, index_of_id, is_surrounded, is_valid_step, is_walkable,
    };

    pub const TEAM_SIZE: u8 = 6;

    /// Re-reads every cap referenced by the game from the world.
    fn alive_caps(world: @dojo::world::WorldStorage, game: @Game) -> Array<Cap> {
        let mut caps = ArrayTrait::new();
        let mut i: usize = 0;
        while i < game.caps_ids.len() {
            let cap: Cap = world.read_model(*game.caps_ids[i]);
            caps.append(cap);
            i += 1;
        }
        caps
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn rules_version(self: @ContractState) -> u8 {
            2
        }

        fn create_game(ref self: ContractState, p2: ContractAddress) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p2, LAYOUT_PERIMETER_5X5)
        }

        fn create_game_with_layout(
            ref self: ContractState, p2: ContractAddress, layout: u8,
        ) -> u64 {
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
            assert!(game.player1 != 0, "Game not found");
            assert!(!game.over, "Game is over");
            assert!(turn.len() <= 32, "Too many actions");
            let slot: u8 = (game.turn_count % 2).try_into().unwrap();
            let caller: felt252 = get_caller_address().into();
            assert!(
                caller == (if slot == 0 {
                    game.player1
                } else {
                    game.player2
                }), "Not your turn",
            );
            let mut energy = game.energy;
            let mut actions: u8 = 1;
            let mut moves: u8 = 0;
            let mut used_abilities: Array<u64> = array![];
            let mut effects = self._load_effects(game_id, @game);
            let set: Set = world.read_model(game.set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };

            for action in turn.span() {
                assert!(!game.over, "Action after victory");
                // Every preceding action/ability has been persisted and resolved.
                let mut caps = alive_caps(@world, @game);
                let idx = index_of_id(@caps, *action.cap_id);
                assert!(idx < caps.len(), "Cap not found");
                let mut cap = *caps.at(idx);
                assert!(cap.player_slot == slot && cap.owner == caller, "Not your cap");
                assert!(cap.location != Location::Dead, "Cap is dead");
                assert!(cap.stunned_turns == 0, "Cap is stunned");
                let def = dispatcher.get_cap_type(cap.cap_type).expect('Unknown cap type');
                match *action.action_type {
                    ActionType::Play(pos) => {
                        spend_action(ref actions, ref moves, false);
                        assert!(cap.location == Location::Bench, "Not on bench");
                        assert!(cap.available_turn <= game.turn_count, "Capture cooldown");
                        let mut hand: Hand = world.read_model((game_id, slot));
                        assert!(
                            is_in_hand(@hand, @caps, game.turn_count, cap.id), "Piece not in hand",
                        );
                        let deploy = if slot == 0 {
                            get_p1_deploy_spot(game.layout)
                        } else {
                            get_p2_deploy_spot(game.layout)
                        };
                        assert!(pos == deploy, "Must play at deploy spot");
                        assert!(!has_cap_at(@caps, pos), "Tile occupied");
                        cap.location = Location::Board(pos);
                        world.write_model(@cap);
                        requeue(ref hand, cap.id);
                        world.write_model(@hand);
                    },
                    ActionType::Move(pos) => {
                        spend_action(ref actions, ref moves, true);
                        let from = get_position(@cap).expect('Not on board');
                        assert!(is_valid_step(game.layout, from, pos), "Must move one step");
                        let target_idx = index_at(@caps, pos);
                        if target_idx < caps.len() {
                            let target = *caps.at(target_idx);
                            assert!(target.player_slot != slot, "Friendly tile occupied");
                            let target_def = dispatcher
                                .get_cap_type(target.cap_type)
                                .expect('Unknown target');
                            let mut attack = def.attack
                                + conditional_attack_bonus(def.passive, cap, @caps);
                            // Consume next-attack buffs only on contact combat.
                            let mut remaining = array![];
                            for e in effects.span() {
                                let mut effect = *e;
                                if effect.target == EffectTarget::Cap(cap.id) {
                                    match effect.effect_type {
                                        EffectType::DamageBuff(n) |
                                        EffectType::AttackBonus(n) => {
                                            attack += n.into();
                                            effect.trigger();
                                        },
                                        _ => {},
                                    }
                                }
                                if effect.remaining_triggers > 0 {
                                    remaining.append(effect);
                                }
                            }
                            effects = remaining;
                            attack = apply_damage_reduction(target_def.passive, attack);
                            apply_damage(
                                ref caps, SetOpDamage { target_cap: target.id, amount: attack },
                            );
                            let damaged = *caps.at(target_idx);
                            world.write_model(@damaged);
                            if damaged.location == Location::Dead {
                                cap.location = Location::Board(pos);
                            }
                        } else {
                            cap.location = Location::Board(pos);
                        }
                        world.write_model(@cap);
                    },
                    ActionType::Ability(pos) => {
                        let from = get_position(@cap).expect('Not on board');
                        for id in used_abilities.span() {
                            assert!(*id != cap.id, "Ability already used");
                        }
                        assert!(def.ability_target != TargetType::None, "No ability");
                        assert!(energy >= def.ability_cost, "Not enough energy");
                        if def.ability_target == TargetType::SelfCap {
                            assert!(pos == from, "Must target self");
                        } else {
                            assert!(is_walkable(game.layout, pos), "Invalid target tile");
                            let dx = if from.x > pos.x {
                                from.x - pos.x
                            } else {
                                pos.x - from.x
                            };
                            let dy = if from.y > pos.y {
                                from.y - pos.y
                            } else {
                                pos.y - from.y
                            };
                            let mut in_range = false;
                            for off in def.ability_range.span() {
                                if *off.x == dx && *off.y == dy {
                                    in_range = true;
                                }
                            }
                            assert!(in_range, "Target out of range");
                            let ti = index_at(@caps, pos);
                            match def.ability_target {
                                TargetType::TeamCap => {
                                    assert!(ti < caps.len(), "No target");
                                    assert!(*caps.at(ti).player_slot == slot, "Not friendly");
                                },
                                TargetType::OpponentCap => {
                                    assert!(ti < caps.len(), "No target");
                                    assert!(*caps.at(ti).player_slot != slot, "Not enemy");
                                },
                                TargetType::AnyCap => { assert!(ti < caps.len(), "No target"); },
                                _ => {},
                            }
                        }
                        energy -= def.ability_cost;
                        used_abilities.append(cap.id);
                        let mut infos = array![];
                        for c in caps.span() {
                            if let Location::Board(p) = c.location {
                                infos
                                    .append(
                                        CapInfo {
                                            id: *c.id,
                                            owner: *c.owner,
                                            player_slot: *c.player_slot,
                                            cap_type: *c.cap_type,
                                            x: *p.x,
                                            y: *p.y,
                                            health: *c.health,
                                        },
                                    );
                            }
                        }
                        let ctx = AbilityContext {
                            game_id,
                            layout: game.layout,
                            turn_count: game.turn_count,
                            energy,
                            actor: ActorInfo {
                                id: cap.id,
                                owner: cap.owner,
                                player_slot: slot,
                                cap_type: cap.cap_type,
                                x: from.x,
                                y: from.y,
                                health: cap.health,
                            },
                            caps: infos.span(),
                            effects: _effect_snapshots(@effects),
                        };
                        let output = dispatcher.activate_ability(ctx, pos);
                        assert!(
                            output.ops.len() <= set.max_ops_per_ability.into(),
                            "Ability op budget exceeded",
                        );
                        for op in output.ops {
                            match *op {
                                SetOp::ExtraMoves(n) => {
                                    assert!(n <= 4 && moves + n <= 8, "Move bonus too large");
                                    moves += n;
                                },
                                SetOp::ExtraActions(n) => {
                                    assert!(n <= 4 && actions + n <= 8, "Action bonus too large");
                                    actions += n;
                                },
                                SetOp::Heal(h) => {
                                    let ti = index_of_id(@caps, h.target_cap);
                                    if ti < caps.len() {
                                        let td = dispatcher
                                            .get_cap_type(*caps.at(ti).cap_type)
                                            .expect('Unknown target');
                                        apply_op(
                                            ref caps,
                                            ref effects,
                                            cap.id,
                                            slot,
                                            game.id,
                                            game.layout,
                                            ref game.next_effect_id,
                                            SetOp::Heal(
                                                SetOpHeal {
                                                    target_cap: h.target_cap,
                                                    amount: h.amount,
                                                    max_health: td.max_health,
                                                },
                                            ),
                                        );
                                    }
                                },
                                SetOp::Summon(_) => panic!("Summon not supported"),
                                _ => {
                                    apply_op(
                                        ref caps,
                                        ref effects,
                                        cap.id,
                                        slot,
                                        game.id,
                                        game.layout,
                                        ref game.next_effect_id,
                                        *op,
                                    );
                                },
                            }
                        }
                        for c in caps.span() {
                            world.write_model(c);
                        };
                    },
                }
                self._resolve_board(ref game, ref effects);
            }
            if slot == 0 {
                game.p1_energy = energy;
            } else {
                game.p2_energy = energy;
            }
            game.energy = energy;
            if !game.over {
                self._end_turn(ref game, ref effects, slot);
                self._resolve_board(ref game, ref effects);
            }
            game.turn_count += 1;
            if !game.over {
                self._begin_turn(ref game, ref effects);
            }
            self._save_effects(ref game, effects);
            game.last_action_timestamp = get_block_timestamp();
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
            }
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
            let set = Set { id: set_id, address, max_on_board, max_cap_types, max_ops_per_ability };
            world.write_model(@set);
            set_id
        }

        fn get_cap_data(self: @ContractState, game_id: u64, cap_type_id: u16) -> Option<CapType> {
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
            let game: Game = world.read_model(game_id);
            let caps = alive_caps(@world, @game);
            let window = caps::logic::hand::window_ids(@hand, @caps, game.turn_count);
            Option::Some((hand, window.span()))
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _create_game(
            ref self: ContractState, p1: ContractAddress, p2: ContractAddress, layout: u8,
        ) -> u64 {
            let mut world = self.world_default();
            assert!(layout <= 3, "Unknown layout");
            assert!(p1.is_non_zero() && p2.is_non_zero(), "Invalid player");
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
                winner_slot: 2,
                caps_ids: ArrayTrait::new(),
                effect_ids: ArrayTrait::new(),
                energy: 0,
                p1_energy: 0,
                p2_energy: 0,
                next_effect_id: 1,
                last_action_timestamp: 0,
            };

            let mut cap_counter = global.cap_counter;

            let mut i: u8 = 0;
            while i < TEAM_SIZE {
                let cap_type: u16 = if i == 0 {
                    0
                } else {
                    i.into()
                };
                let (hp, _, _, _) = self._stats(game.set_id, cap_type);

                cap_counter += 1;
                let cap1 = Cap {
                    id: cap_counter,
                    owner: p1_felt,
                    player_slot: 0,
                    cap_type,
                    set_id: game.set_id,
                    location: Location::Bench,
                    health: hp,
                    shield: 0,
                    stunned_turns: 0,
                    available_turn: 0,
                };
                world.write_model(@cap1);
                game.caps_ids.append(cap1.id);

                cap_counter += 1;
                let cap2 = Cap {
                    id: cap_counter,
                    owner: p2_felt,
                    player_slot: 1,
                    cap_type,
                    set_id: game.set_id,
                    location: Location::Bench,
                    health: hp,
                    shield: 0,
                    stunned_turns: 0,
                    available_turn: 0,
                };
                world.write_model(@cap2);
                game.caps_ids.append(cap2.id);

                i += 1;
            }

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
            }
            let hand1 = Hand { game_id, player_slot: 0, roster: p1_roster, hand_size: HAND_SIZE };
            let hand2 = Hand { game_id, player_slot: 1, roster: p2_roster, hand_size: HAND_SIZE };
            world.write_model(@hand1);
            world.write_model(@hand2);

            let mut effects = array![];
            self._begin_turn(ref game, ref effects);
            world.write_model(@game);
            world.write_model(@global);

            game_id
        }

        /// Fetch stats from the game's set contract. Falls back to v1
        /// stats if the set doesn't define the type (never happens for
        /// registered sets, but keeps the compiler happy).
        fn _stats(ref self: ContractState, set_id: u64, cap_type: u16) -> (u16, u8, u8, u16) {
            let world = self.world_default();
            let set: Set = world.read_model(set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };
            match dispatcher.get_cap_type(cap_type) {
                Option::Some(ct) => (ct.max_health, ct.play_cost, ct.move_cost, ct.attack),
                Option::None => (8, 1, 1, 2),
            }
        }

        fn _load_effects(ref self: ContractState, game_id: u64, game: @Game) -> Array<Effect> {
            let world = self.world_default();
            let mut effects = ArrayTrait::new();
            let mut i: usize = 0;
            while i < game.effect_ids.len() {
                let e: Effect = world.read_model((game_id, *game.effect_ids[i]));
                if e.remaining_triggers > 0 {
                    effects.append(e);
                }
                i += 1;
            }
            effects
        }

        /// Arrival at a goal ends the game immediately. Otherwise capture simultaneously.
        fn _resolve_board(ref self: ContractState, ref game: Game, ref effects: Array<Effect>) {
            let mut world = self.world_default();
            let caps = alive_caps(@world, @game);
            for c in caps.span() {
                if is_goal(*c) {
                    game.over = true;
                    game.winner = *c.owner;
                    game.winner_slot = *c.player_slot;
                    return;
                }
            }
            let mut captured: Array<u64> = array![];
            for c in caps.span() {
                if let Location::Board(pos) = c.location {
                    if is_surrounded(@caps, game.layout, *pos) {
                        captured.append(*c.id);
                    }
                }
            }
            for id in captured.span() {
                let mut c: Cap = world.read_model(*id);
                c.location = Location::Bench;
                let (hp, _, _, _) = self._stats(game.set_id, c.cap_type);
                c.health = hp;
                c.shield = 0;
                c.stunned_turns = 0;
                c.available_turn = capture_ready_turn(game.turn_count, c.player_slot);
                world.write_model(@c);
                let mut hand: Hand = world.read_model((game.id, c.player_slot));
                requeue(ref hand, c.id);
                world.write_model(@hand);
            }
            let current = alive_caps(@world, @game);
            // Effects cannot keep ticking on captured or dead pieces.
            let mut remaining = array![];
            for e in effects.span() {
                if let EffectTarget::Cap(id) = e.target {
                    let idx = index_of_id(@current, *id);
                    if idx < current.len()
                        && is_on_board(current.at(idx))
                        && *e.remaining_triggers > 0 {
                        remaining.append(*e);
                    }
                }
            }
            effects = remaining;
        }

        /// Prepare and store next player's actual budget so reads and validation agree.
        fn _begin_turn(ref self: ContractState, ref game: Game, ref effects: Array<Effect>) {
            let mut world = self.world_default();
            let slot: u8 = (game.turn_count % 2).try_into().unwrap();
            let mut caps = alive_caps(@world, @game);
            let sources = caps.clone();
            for source in sources.span() {
                if *source.player_slot == slot && is_on_board(source) {
                    let passive = self._get_passive(game.set_id, *source.cap_type);
                    let ops = caps::models::set_data::AuraTrait::aura_ops(*source, passive, @caps);
                    for op in ops.span() {
                        if let SetOp::ApplyEffect(a) = *op {
                            let mut exists = false;
                            for e in effects.span() {
                                if *e.target == EffectTarget::Cap(a.target_cap)
                                    && *e.effect_type == a.effect {
                                    exists = true;
                                }
                            }
                            if !exists {
                                apply_op(
                                    ref caps,
                                    ref effects,
                                    *source.id,
                                    slot,
                                    game.id,
                                    game.layout,
                                    ref game.next_effect_id,
                                    *op,
                                );
                            }
                        }
                    };
                }
            }
            let mut income: u16 = BASE_INCOME.into() + objective_income(@caps, slot).into();
            for c in caps.span() {
                if *c.player_slot == slot && is_on_board(c) {
                    let passive = self._get_passive(game.set_id, *c.cap_type);
                    if let PassiveType::EnergyGeneration(n) = passive.passive_type {
                        income += n.into();
                    }
                }
            }
            let mut remaining = array![];
            for e in effects.span() {
                let mut effect = *e;
                if let EffectTarget::Cap(id) = effect.target {
                    let mut c: Cap = world.read_model(id);
                    if c.player_slot == slot && is_on_board(@c) {
                        match effect.effect_type {
                            EffectType::ExtraEnergy(n) => {
                                income += n.into();
                                effect.trigger();
                            },
                            EffectType::Stun(_) => {
                                c.stunned_turns = 1;
                                world.write_model(@c);
                                effect.trigger();
                            },
                            _ => {},
                        }
                    }
                }
                if effect.remaining_triggers > 0 {
                    remaining.append(effect);
                }
            }
            effects = remaining;
            let stored = if slot == 0 {
                game.p1_energy
            } else {
                game.p2_energy
            };
            game.energy = add_energy(stored, income);
            if slot == 0 {
                game.p1_energy = game.energy;
            } else {
                game.p2_energy = game.energy;
            }
        }

        fn _end_turn(
            ref self: ContractState, ref game: Game, ref effects: Array<Effect>, slot: u8,
        ) {
            let mut world = self.world_default();
            let mut caps = alive_caps(@world, @game);
            let mut remaining = array![];
            for e in effects.span() {
                let mut effect = *e;
                if let EffectTarget::Cap(id) = effect.target {
                    let idx = index_of_id(@caps, id);
                    if idx < caps.len()
                        && *caps.at(idx).player_slot == slot
                        && is_on_board(caps.at(idx)) {
                        match effect.effect_type {
                            EffectType::DOT(n) => {
                                apply_damage(
                                    ref caps, SetOpDamage { target_cap: id, amount: n.into() },
                                );
                                effect.trigger();
                            },
                            EffectType::Heal(n) => {
                                let (hp, _, _, _) = self
                                    ._stats(game.set_id, *caps.at(idx).cap_type);
                                apply_heal(
                                    ref caps,
                                    SetOpHeal { target_cap: id, amount: n.into(), max_health: hp },
                                );
                                effect.trigger();
                            },
                            _ => {},
                        }
                    }
                }
                if effect.remaining_triggers > 0 {
                    remaining.append(effect);
                }
            }
            effects = remaining;
            for c in caps.span() {
                let mut cap = *c;
                if cap.player_slot == slot {
                    cap.stunned_turns = 0;
                    if is_on_board(@cap) {
                        let passive = self._get_passive(game.set_id, cap.cap_type);
                        if let PassiveType::Regeneration(r) = passive.passive_type {
                            let (hp, _, _, _) = self._stats(game.set_id, cap.cap_type);
                            let healed: u32 = cap.health.into() + r.amount.into();
                            cap
                                .health =
                                    if healed > hp.into() {
                                        hp
                                    } else {
                                        healed.try_into().unwrap()
                                    };
                        }
                    }
                }
                world.write_model(@cap);
            };
        }

        fn _save_effects(ref self: ContractState, ref game: Game, effects: Array<Effect>) {
            let mut world = self.world_default();
            for id in game.effect_ids.span() {
                let old: Effect = world.read_model((game.id, *id));
                world.erase_model(@old);
            }
            game.effect_ids = array![];
            for e in effects.span() {
                let mut effect = *e;
                effect.game_id = game.id;
                if effect.remaining_triggers > 0 {
                    world.write_model(@effect);
                    game.effect_ids.append(effect.effect_id);
                }
            };
        }

        /// Fetch the passive for a piece type from the set contract.
        /// Returns None if the set doesn't define it.
        fn _get_passive(ref self: ContractState, set_id: u64, cap_type: u16) -> Passive {
            let world = self.world_default();
            let set: Set = world.read_model(set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };
            match dispatcher.get_cap_type(cap_type) {
                Option::Some(ct) => ct.passive,
                Option::None => Passive { passive_type: PassiveType::None },
            }
        }

        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"caps")
        }
    }
}
