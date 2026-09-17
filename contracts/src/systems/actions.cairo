use caps::logic::track::{
    LAYOUT_PERIMETER_5X5, get_p1_deploy_spot, get_p2_deploy_spot, is_valid_step, is_walkable,
};
use caps::models::cap::{Cap, Location};
use caps::models::game::{Action, Game, Hand, Vec2};
use caps::models::game_clock::GameClock;
use caps::models::set_data::CapType;
use caps::models::stack::AbilityStack;
use caps::models::turn_record::TurnRecord;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IActions<T> {
    fn rules_version(self: @T) -> u8;
    fn get_game_board(self: @T, game_id: u64) -> u64;
    fn create_game_with_board(ref self: T, p2: ContractAddress, board_id: u64) -> u64;
    fn create_solo_game_with_board(ref self: T, board_id: u64) -> u64;
    fn get_clock(self: @T, game_id: u64) -> (GameClock, u64);
    fn claim_timeout(ref self: T, game_id: u64, expected_turn: u64);
    fn get_turn(self: @T, game_id: u64, turn: u64) -> Option<TurnRecord>;
    fn get_game_count(self: @T) -> u64;
    fn get_stack(self: @T, game_id: u64) -> AbilityStack;
    fn take_turn_if_current(ref self: T, game_id: u64, expected_turn: u64, turn: Array<Action>);
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
    use caps::logic::passives::bonus;
    use caps::logic::rules::{
        BASE_INCOME, add_energy, capture_ready_turn, is_goal, objective_income, spend_action,
    };
    use caps::logic::stack::{counter, pop_ready, resolve, schedule};
    use caps::logic::track::{within_range, BoardGeometry};
    use caps::models::board::GameBoard;
    use caps::systems::boards::{IBoardsDispatcher, IBoardsDispatcherTrait};
    use dojo::world::WorldStorageTrait;
    use caps::models::cap::{Cap, Location, get_position, is_on_board};
    use caps::models::effect::{Effect, EffectTarget, EffectTrait, EffectType, PassiveKind};
    use caps::models::game::{Action, ActionType, Game, Global, Hand};
    use caps::models::game_clock::{GameClock, finish_turn, fresh, remaining};
    use caps::models::set::{ISetInterfaceDispatcher, ISetInterfaceDispatcherTrait, Set};
    use caps::models::set_data::{
        AbilityContext, ActorInfo, CapInfo, CapType, SetOp, SetOpDamage, SetOpHeal, TargetType,
    };
    use caps::models::stack::AbilityStack;
    use caps::models::turn_record::{TurnRecord, snapshot};
    use core::num::traits::{SaturatingAdd, Zero};
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::{
        IActions, LAYOUT_PERIMETER_5X5, _effect_snapshots, get_p1_deploy_spot, get_p2_deploy_spot,
        has_cap_at, index_at, index_of_id, is_surrounded, is_valid_step, is_walkable,
    };

    pub const TEAM_SIZE: u8 = 7;

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
            7
        }

        fn get_game_board(self: @ContractState, game_id: u64) -> u64 {
            let binding: GameBoard = self.world_default().read_model(game_id);
            binding.board_id
        }
        fn create_game_with_board(ref self: ContractState, p2: ContractAddress, board_id: u64) -> u64 {
            assert!(board_id > 0, "Board required");
            self._create_game(get_caller_address(), p2, 255, board_id)
        }
        fn create_solo_game_with_board(ref self: ContractState, board_id: u64) -> u64 {
            assert!(board_id > 0, "Board required");
            let caller = get_caller_address();
            self._create_game(caller, caller, 255, board_id)
        }
        fn get_clock(self: @ContractState, game_id: u64) -> (GameClock, u64) {
            let world = self.world_default();
            let mut clock: GameClock = world.read_model(game_id);
            clock.game_id = game_id;
            (clock, get_block_timestamp())
        }

        fn claim_timeout(ref self: ContractState, game_id: u64, expected_turn: u64) {
            let world = self.world_default();
            let mut game: Game = world.read_model(game_id);
            assert!(game.player1 != 0 && !game.over, "Game unavailable");
            assert!(game.turn_count == expected_turn, "Stale turn");
            let slot: u8 = (game.turn_count % 2).try_into().unwrap();
            let caller: felt252 = get_caller_address().into();
            assert!(
                caller == (if slot == 0 {
                    game.player2
                } else {
                    game.player1
                }),
                "Only opponent may claim",
            );
            let mut clock: GameClock = world.read_model(game_id);
            let now = get_block_timestamp();
            assert!(clock.enabled && remaining(clock, slot, now) == 0, "Time remains");
            self._lose_on_time(ref game, ref clock, slot, now);
        }

        fn get_turn(self: @ContractState, game_id: u64, turn: u64) -> Option<TurnRecord> {
            let world = self.world_default();
            let record: TurnRecord = world.read_model((game_id, turn));
            if record.recorded {
                Option::Some(record)
            } else {
                Option::None
            }
        }

        fn get_stack(self: @ContractState, game_id: u64) -> AbilityStack {
            let world = self.world_default();
            let mut stack: AbilityStack = world.read_model(game_id);
            stack.game_id = game_id;
            stack
        }

        fn get_game_count(self: @ContractState) -> u64 {
            let world = self.world_default();
            let global: Global = world.read_model(0);
            global.games_counter
        }

        fn take_turn_if_current(
            ref self: ContractState, game_id: u64, expected_turn: u64, turn: Array<Action>,
        ) {
            let world = self.world_default();
            let game: Game = world.read_model(game_id);
            assert!(game.turn_count == expected_turn, "Turn changed");
            self.take_turn(game_id, turn);
        }

        fn create_game(ref self: ContractState, p2: ContractAddress) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p2, LAYOUT_PERIMETER_5X5, 0)
        }

        fn create_game_with_layout(
            ref self: ContractState, p2: ContractAddress, layout: u8,
        ) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p2, layout, 0)
        }

        fn create_solo_game(ref self: ContractState) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p1, LAYOUT_PERIMETER_5X5, 0)
        }

        fn create_solo_game_with_layout(ref self: ContractState, layout: u8) -> u64 {
            let p1 = get_caller_address();
            self._create_game(p1, p1, layout, 0)
        }

        fn take_turn(ref self: ContractState, game_id: u64, turn: Array<Action>) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);
            assert!(game.player1 != 0, "Game not found");
            assert!(!game.over, "Game is over");
            let slot: u8 = (game.turn_count % 2).try_into().unwrap();
            let caller: felt252 = get_caller_address().into();
            assert!(
                caller == (if slot == 0 {
                    game.player1
                } else {
                    game.player2
                }), "Not your turn",
            );
            let now = get_block_timestamp();
            let mut clock: GameClock = world.read_model(game_id);
            if !clock.enabled {
                clock = fresh(game_id, now);
            }
            if remaining(clock, slot, now) == 0 {
                self._lose_on_time(ref game, ref clock, slot, now);
                return;
            }
            let board = self._board(@game);
            assert!(turn.len() <= 32, "Too many actions");
            let mut stack: AbilityStack = world.read_model(game_id);
            stack.game_id = game_id;
            let energy_before = game.energy;
            let before = snapshot(@alive_caps(@world, @game));
            let mut stack_before = array![];
            for entry in stack.entries.span() {
                stack_before.append(*entry);
            }
            let mut resolved = array![];
            let mut energy = game.energy;
            let mut actions: u8 = 1;
            let mut moves: u8 = 0;
            let mut used_abilities: Array<u64> = array![];
            let mut effects = self._load_effects(game_id, @game);
            let set: Set = world.read_model(game.set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };

            let definitions = self._definitions(game.set_id, @alive_caps(@world, @game));
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
                let pending_target = match *action.action_type {
                    ActionType::StackAbility(id) => Option::Some(id),
                    _ => Option::None,
                };
                let action_type = match *action.action_type {
                    ActionType::StackAbility(_) => ActionType::Ability(
                        get_position(@cap).expect('Not on board'),
                    ),
                    other => other,
                };
                match action_type {
                    ActionType::Play(pos) => {
                        spend_action(ref actions, ref moves, false);
                        assert!(cap.location == Location::Bench, "Not on bench");
                        assert!(cap.available_turn <= game.turn_count, "Capture cooldown");
                        let mut hand: Hand = world.read_model((game_id, slot));
                        assert!(
                            is_in_hand(@hand, @caps, game.turn_count, cap.id), "Piece not in hand",
                        );
                        let deploy = if slot == 0 {
                            get_p1_deploy_spot(board)
                        } else {
                            get_p2_deploy_spot(board)
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
                        assert!(is_valid_step(board, from, pos), "Must move one step");
                        let target_idx = index_at(@caps, pos);
                        if target_idx < caps.len() {
                            let target = *caps.at(target_idx);
                            assert!(target.player_slot != slot, "Friendly tile occupied");
                            let mut attack = def
                                .attack
                                .saturating_add(
                                    bonus(
                                        PassiveKind::AttackBonus,
                                        cap,
                                        @caps,
                                        @definitions,
                                        board,
                                    ),
                                );
                            // Consume next-attack buffs only on contact combat.
                            let mut remaining = array![];
                            for e in effects.span() {
                                let mut effect = *e;
                                if effect.target == EffectTarget::Cap(cap.id) {
                                    match effect.effect_type {
                                        EffectType::DamageBuff(n) |
                                        EffectType::AttackBonus(n) => {
                                            attack = attack.saturating_add(n.into());
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
                            let reduction = bonus(
                                PassiveKind::DamageReduction,
                                target,
                                @caps,
                                @definitions,
                                board,
                            );
                            attack = if attack > reduction {
                                attack - reduction
                            } else {
                                0
                            };
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
                        if let Option::Some(target_id) = pending_target {
                            assert!(
                                def.ability_target == TargetType::AnyPending
                                    || def.ability_target == TargetType::EnemyPending
                                    || def.ability_target == TargetType::AllyPending,
                                "Not a stack ability",
                            );
                            let mut found = false;
                            for entry in stack.entries.span() {
                                if *entry.id == target_id {
                                    found = true;
                                    if def.ability_target == TargetType::EnemyPending {
                                        assert!(*entry.player_slot != slot, "Not enemy effect");
                                    }
                                    if def.ability_target == TargetType::AllyPending {
                                        assert!(*entry.player_slot == slot, "Not friendly effect");
                                    }
                                }
                            }
                            assert!(found, "Pending effect missing");
                        } else if def.ability_target == TargetType::SelfCap {
                            assert!(pos == from, "Must target self");
                        } else {
                            assert!(
                                def.ability_target != TargetType::AnyPending
                                    && def.ability_target != TargetType::EnemyPending
                                    && def.ability_target != TargetType::AllyPending,
                                "Choose a stack effect",
                            );
                            assert!(is_walkable(board, pos), "Invalid target tile");
                            let range: u16 = def.ability_range.into();
                            let range = range
                                .saturating_add(
                                    bonus(
                                        PassiveKind::AbilityRangeBonus,
                                        cap,
                                        @caps,
                                        @definitions,
                                        board,
                                    ),
                                );
                            assert!(
                                within_range(board, from, pos, range), "Target out of range",
                            );
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
                            stack: stack.entries.span(),
                        };
                        let output = match pending_target {
                            Option::Some(id) => dispatcher.activate_stack_ability(ctx, id),
                            Option::None => dispatcher.activate_ability(ctx, pos),
                        };
                        assert!(
                            output.ops.len() <= set.max_ops_per_ability.into(),
                            "Ability op budget exceeded",
                        );
                        for op in output.ops {
                            match *op {
                                SetOp::Schedule(request) => {
                                    schedule(
                                        ref stack,
                                        cap.id,
                                        slot,
                                        game.turn_count,
                                        board,
                                        request,
                                    );
                                },
                                SetOp::CounterPending(id) => { counter(ref stack, id); },
                                SetOp::ExtraMoves(n) => {
                                    assert!(n <= 4 && moves + n <= 8, "Move bonus too large");
                                    moves += n;
                                },
                                SetOp::ExtraActions(n) => {
                                    assert!(n <= 4 && actions + n <= 8, "Action bonus too large");
                                    actions += n;
                                },
                                SetOp::Damage(d) => {
                                    let ti = index_of_id(@caps, d.target_cap);
                                    if ti < caps.len() {
                                        let reduction = bonus(
                                            PassiveKind::DamageReduction,
                                            *caps.at(ti),
                                            @caps,
                                            @definitions,
                                            board,
                                        );
                                        let amount = if d.amount > reduction {
                                            d.amount - reduction
                                        } else {
                                            0
                                        };
                                        apply_damage(
                                            ref caps,
                                            SetOpDamage { target_cap: d.target_cap, amount },
                                        );
                                    }
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
                                            board,
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
                                        board,
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
                    ActionType::StackAbility(_) => panic!("Unreachable stack action"),
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
            if !game.over {
                let boundary = game.turn_count + 1;
                loop {
                    let entry = match pop_ready(ref stack, boundary) {
                        Option::Some(entry) => entry,
                        Option::None => { break; },
                    };
                    resolved.append(entry);
                    let mut caps = alive_caps(@world, @game);
                    let current_definitions = self._definitions(game.set_id, @caps);
                    resolve(entry, ref caps, @current_definitions, board);
                    for c in caps.span() {
                        world.write_model(c);
                    }
                    self._resolve_board(ref game, ref effects);
                    if game.over {
                        break;
                    }
                };
            }
            if game.over {
                stack.entries = array![];
            }
            let mut stack_after = array![];
            for entry in stack.entries.span() {
                stack_after.append(*entry);
            }
            world.write_model(@stack);
            finish_turn(ref clock, slot, now, !game.over);
            world.write_model(@clock);
            let completed_turn = game.turn_count;
            game.turn_count += 1;
            if !game.over {
                self._begin_turn(ref game, ref effects);
            }
            self._save_effects(ref game, effects);
            game.last_action_timestamp = get_block_timestamp();
            world.write_model(@game);
            world
                .write_model(
                    @TurnRecord {
                        game_id,
                        turn: completed_turn,
                        recorded: true,
                        player_slot: slot,
                        actions: turn,
                        before,
                        after: snapshot(@alive_caps(@world, @game)),
                        stack_before,
                        stack_after,
                        resolved,
                        energy_before,
                        energy_after: energy,
                    },
                );
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
        fn _geometry(self: @ContractState, layout: u8, board_id: u64) -> BoardGeometry {
            let (address, _) = self.world_default().dns(@"boards").expect('Board registry missing');
            IBoardsDispatcher {contract_address:address}.get_geometry(layout,board_id)
        }
        fn _board(self: @ContractState, game: @Game) -> BoardGeometry {
            let id = if *game.layout == 255 {
                let binding: GameBoard = self.world_default().read_model(*game.id);
                binding.board_id
            } else { 0 };
            self._geometry(*game.layout,id)
        }

        fn _lose_on_time(
            ref self: ContractState, ref game: Game, ref clock: GameClock, slot: u8, now: u64,
        ) {
            let mut world = self.world_default();
            game.over = true;
            game.winner_slot = 1 - slot;
            game.winner = if slot == 0 {
                game.player2
            } else {
                game.player1
            };
            game.turn_count += 1;
            game.last_action_timestamp = now;
            if slot == 0 {
                clock.p1_seconds = 0;
            } else {
                clock.p2_seconds = 0;
            }
            clock.timed_out_slot = slot;
            clock.running_since = now;
            let mut stack: AbilityStack = world.read_model(game.id);
            stack.game_id = game.id;
            stack.entries = array![];
            world.write_model(@stack);
            world.write_model(@clock);
            world.write_model(@game);
        }

        fn _create_game(
            ref self: ContractState, p1: ContractAddress, p2: ContractAddress, layout: u8, board_id: u64,
        ) -> u64 {
            let mut world = self.world_default();
            let geometry = self._geometry(layout,board_id);
            let (width, _) = caps::logic::track::get_board_dimensions(geometry);
            assert!(width > 0, "Unknown layout");
            assert!(p1.is_non_zero() && p2.is_non_zero(), "Invalid player");
            let mut global: Global = world.read_model(0);

            let game_id = global.games_counter + 1;
            if board_id > 0 { world.write_model(@GameBoard { game_id, board_id }); }
            world.write_model(@fresh(game_id, get_block_timestamp()));
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
            let board = self._board(@game);
            let caps = alive_caps(@world, @game);
            for c in caps.span() {
                if is_goal(*c, board) {
                    game.over = true;
                    game.winner = *c.owner;
                    game.winner_slot = *c.player_slot;
                    return;
                }
            }
            let mut captured: Array<u64> = array![];
            for c in caps.span() {
                if let Location::Board(pos) = c.location {
                    if is_surrounded(@caps, board, *pos) {
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
            let board = self._board(@game);
            let slot: u8 = (game.turn_count % 2).try_into().unwrap();
            let mut caps = alive_caps(@world, @game);
            let definitions = self._definitions(game.set_id, @caps);
            let mut income: u16 = BASE_INCOME.into()
                + objective_income(@caps, slot, board).into();
            for c in caps.span() {
                if *c.player_slot == slot && is_on_board(c) {
                    income = income
                        .saturating_add(
                            bonus(
                                PassiveKind::EnergyGeneration, *c, @caps, @definitions, board,
                            ),
                        );
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
                                income = income.saturating_add(n.into());
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
            let board = self._board(@game);
            let mut world = self.world_default();
            let mut caps = alive_caps(@world, @game);
            let definitions = self._definitions(game.set_id, @caps);
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
                                let reduction = bonus(
                                    PassiveKind::DamageReduction,
                                    *caps.at(idx),
                                    @caps,
                                    @definitions,
                                    board,
                                );
                                let damage: u16 = n.into();
                                let amount = if damage > reduction {
                                    damage - reduction
                                } else {
                                    0
                                };
                                apply_damage(ref caps, SetOpDamage { target_cap: id, amount });
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
                        let amount = bonus(
                            PassiveKind::Regeneration, cap, @caps, @definitions, board,
                        );
                        let (hp, _, _, _) = self._stats(game.set_id, cap.cap_type);
                        let healed = cap.health.saturating_add(amount);
                        cap.health = if healed > hp {
                            hp
                        } else {
                            healed
                        };
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

        /// Read each piece definition once per phase. Passive conditions use fresh board state.
        fn _definitions(ref self: ContractState, set_id: u64, caps: @Array<Cap>) -> Array<CapType> {
            let world = self.world_default();
            let set: Set = world.read_model(set_id);
            let dispatcher = ISetInterfaceDispatcher { contract_address: set.address };
            let mut definitions: Array<CapType> = array![];
            for c in caps.span() {
                let mut found = false;
                for d in definitions.span() {
                    if *d.id == *c.cap_type {
                        found = true;
                    }
                }
                if !found {
                    definitions
                        .append(dispatcher.get_cap_type(*c.cap_type).expect('Unknown piece'));
                }
            }
            definitions
        }

        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"caps")
        }
    }
}
