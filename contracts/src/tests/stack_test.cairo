use caps::logic::stack::{counter, pop_ready, schedule};
use caps::models::cap::{Cap, Location};
use caps::models::effect::Relation;
use caps::models::game::{Action, ActionType, Game, Vec2};
use caps::models::set::Set;
use caps::models::stack::{AbilityStack, DelayedImpact, ImpactKind, Schedule, Selection};
use caps::systems::actions::IActionsDispatcherTrait;
use caps::tests::rules_test::{put, setup};
use dojo::model::{ModelStorage, ModelStorageTest};
use dojo::world::{WorldStorage, WorldStorageTrait};

fn energy(ref world: WorldStorage, id: u64) {
    let mut game: Game = world.read_model(id);
    game.energy = 3;
    game.p1_energy = 3;
    game.p2_energy = 3;
    world.write_model_test(@game);
}
fn activate(id: u64, x: u8, y: u8) -> Action {
    Action { cap_id: id, action_type: ActionType::Ability(Vec2 { x, y }) }
}
fn step(id: u64, x: u8, y: u8) -> Action {
    Action { cap_id: id, action_type: ActionType::Move(Vec2 { x, y }) }
}
fn response_set(ref world: WorldStorage) {
    let (address, _) = world.dns(@"response_test_set").unwrap();
    let mut set: Set = world.read_model(0_u64);
    set.address = address;
    world.write_model_test(@set);
}

#[test]
fn announce_then_allow_escape_before_row_damage() {
    let (mut world, api, id) = setup();
    put(ref world, 9, 1, 0);
    put(ref world, 4, 0, 0);
    put(ref world, 3, 3, 0);
    energy(ref world, id);
    api.take_turn(id, array![activate(9, 3, 0)]);
    let pending = api.get_stack(id);
    assert!(
        pending.entries.len() == 1 && *pending.entries.at(0).ready_turn == 2, "public announcement",
    );
    let before: Cap = world.read_model(3_u64);
    assert!(before.health == 6, "not immediate damage");
    api.take_turn(id, array![step(4, 0, 1)]);
    let escaped: Cap = world.read_model(4_u64);
    let stayed: Cap = world.read_model(3_u64);
    assert!(escaped.health == 6 && stayed.health == 2, "select occupants at resolution");
    assert!(api.get_stack(id).entries.is_empty(), "resolved exactly once");
}

#[test]
fn killing_source_does_not_cancel_announced_effect() {
    let (mut world, api, id) = setup();
    put(ref world, 9, 1, 0);
    put(ref world, 4, 0, 0);
    let mut source: Cap = world.read_model(9_u64);
    source.health = 1;
    world.write_model_test(@source);
    energy(ref world, id);
    api.take_turn(id, array![activate(9, 1, 0)]);
    api.take_turn(id, array![step(4, 1, 0)]);
    let source: Cap = world.read_model(9_u64);
    let target: Cap = world.read_model(4_u64);
    assert!(source.location == Location::Dead, "source killed by response");
    assert!(target.health == 2, "effect survived source death");
}

#[test]
fn newer_delayed_shield_blocks_then_resolves_before_older_damage() {
    let (mut world, api, id) = setup();
    response_set(ref world);
    put(ref world, 9, 1, 0);
    put(ref world, 6, 3, 0);
    energy(ref world, id);
    api.take_turn(id, array![activate(9, 3, 0)]);
    api.take_turn(id, array![activate(6, 3, 0)]);
    assert!(api.get_stack(id).entries.len() == 2, "newer unready item blocks older ready item");
    api.take_turn(id, array![]);
    let a: Cap = world.read_model(9_u64);
    let b: Cap = world.read_model(6_u64);
    assert!(
        a.health == 5 && b.health == 10 && a.shield == 0 && b.shield == 0, "shield resolved first",
    );
    assert!(api.get_stack(id).entries.is_empty(), "drained ready stack");
    let record = api.get_turn(id, 2).unwrap();
    assert!(
        record.actions.is_empty() && record.resolved.len() == 2,
        "pass records automatic resolution",
    );
    assert!(
        *record.resolved.at(0).id == 2 && *record.resolved.at(1).id == 1,
        "journal preserves resolution order",
    );
}

#[test]
fn counter_cancels_pending_effect_without_refunding_source() {
    let (mut world, api, id) = setup();
    response_set(ref world);
    put(ref world, 9, 1, 0);
    put(ref world, 8, 3, 0);
    energy(ref world, id);
    api.take_turn(id, array![activate(9, 3, 0)]);
    api.take_turn(id, array![activate(8, 3, 0)]);
    assert!(api.get_stack(id).entries.is_empty(), "counter removed effect");
    let source: Cap = world.read_model(9_u64);
    let game: Game = world.read_model(id);
    assert!(source.health == 5 && game.p1_energy == 1, "no damage and no activation refund");
}

#[test]
fn goal_ends_game_before_delayed_blast_and_clears_stack() {
    let (mut world, api, id) = setup();
    put(ref world, 9, 0, 0);
    put(ref world, 4, 3, 0);
    energy(ref world, id);
    api.take_turn(id, array![activate(9, 3, 0)]);
    api.take_turn(id, array![step(4, 2, 0)]);
    let game: Game = world.read_model(id);
    let winner: Cap = world.read_model(4_u64);
    assert!(
        game.over && game.winner_slot == 1 && winner.health == 6, "goal has immediate priority",
    );
    assert!(api.get_stack(id).entries.is_empty(), "no post-game effects");
}

#[test]
fn stable_ids_and_lifo_readiness() {
    let mut stack = AbilityStack { game_id: 1, next_id: 0, entries: array![] };
    let request = Schedule {
        delay: 1,
        impact: DelayedImpact {
            kind: ImpactKind::Damage,
            selection: Selection::Row(0),
            relation: Relation::Any,
            amount: 4,
        },
    };
    schedule(ref stack, 1, 0, 0, caps::logic::track::legacy(0), request);
    schedule(ref stack, 2, 1, 1, caps::logic::track::legacy(0), request);
    assert!(pop_ready(ref stack, 2).is_none(), "strict stack order");
    counter(ref stack, 2);
    assert!(pop_ready(ref stack, 2).unwrap().id == 1, "counter exposes older ready item");
    schedule(ref stack, 1, 0, 2, caps::logic::track::legacy(0), request);
    assert!(*stack.entries.at(0).id == 3, "ids never reused");
}

#[test]
#[should_panic(expected: ("Delay must be 1 to 8",))]
fn zero_delay_is_rejected() {
    let mut stack = AbilityStack { game_id: 1, next_id: 0, entries: array![] };
    schedule(
        ref stack,
        1,
        0,
        0,
        caps::logic::track::legacy(0),
        Schedule {
            delay: 0,
            impact: DelayedImpact {
                kind: ImpactKind::Damage,
                selection: Selection::Row(0),
                relation: Relation::Any,
                amount: 4,
            },
        },
    );
}

/// Test-only response abilities; the framework does not require expanding the live roster.
#[dojo::contract]
pub mod response_test_set {
    use caps::models::effect::Relation;
    use caps::models::game::Vec2;
    use caps::models::set::ISetInterface;
    use caps::models::set_data::{AbilityContext, CapType, SetOp, SetOutput};
    use caps::models::stack::{DelayedImpact, ImpactKind, Schedule, Selection};
    #[abi(embed_v0)]
    impl Impl of ISetInterface<ContractState> {
        fn get_cap_type(self: @ContractState, id: u16) -> Option<CapType> {
            caps::sets::set_zero::cap_type_of(id)
        }
        fn activate_stack_ability(
            self: @ContractState, ctx: AbilityContext, target_id: u64,
        ) -> SetOutput {
            caps::sets::set_zero::use_stack_ability(ctx, target_id)
        }

        fn activate_ability(self: @ContractState, ctx: AbilityContext, target: Vec2) -> SetOutput {
            if ctx.actor.cap_type == 2 {
                SetOutput {
                    ops: array![
                        SetOp::Schedule(
                            Schedule {
                                delay: 1,
                                impact: DelayedImpact {
                                    kind: ImpactKind::Shield,
                                    selection: Selection::Row(target.y),
                                    relation: Relation::Any,
                                    amount: 4,
                                },
                            },
                        ),
                    ]
                        .span(),
                    events: array![].span(),
                }
            } else if ctx.actor.cap_type == 3 && ctx.stack.len() > 0 {
                SetOutput {
                    ops: array![SetOp::CounterPending(*ctx.stack.at(ctx.stack.len() - 1).id)]
                        .span(),
                    events: array![].span(),
                }
            } else {
                caps::sets::set_zero::use_ability(ctx, target)
            }
        }
    }
}

#[test]
fn delayed_heal_clamps_without_overflow() {
    let mut stack = AbilityStack { game_id: 1, next_id: 0, entries: array![] };
    schedule(
        ref stack,
        99,
        0,
        0,
        caps::logic::track::legacy(0),
        Schedule {
            delay: 1,
            impact: DelayedImpact {
                kind: ImpactKind::Heal,
                selection: Selection::Row(0),
                relation: Relation::Any,
                amount: 65535,
            },
        },
    );
    let entry = pop_ready(ref stack, 2).unwrap();
    let mut caps = array![
        Cap {
            id: 1,
            owner: 0x123,
            player_slot: 0,
            cap_type: 1,
            set_id: 0,
            location: Location::Board(Vec2 { x: 1, y: 0 }),
            health: 1,
            shield: 0,
            stunned_turns: 0,
            available_turn: 0,
        },
    ];
    let definitions = array![caps::sets::set_zero::cap_type_of(1).unwrap()];
    caps::logic::stack::resolve(entry, ref caps, @definitions, caps::logic::track::legacy(0));
    assert!(*caps.at(0).health == 6, "clamped to actual max health");
}

#[test]
fn stack_target_negates_selected_effect_and_records_turn() {
    let (mut world, api, id) = caps::tests::rules_test::setup();
    caps::tests::rules_test::put(ref world, 13, 0, 0);
    let mut game: caps::models::game::Game = world.read_model(id);
    game.energy = 5;
    game.p1_energy = 5;
    world.write_model_test(@game);
    let mut pending = AbilityStack { game_id: id, next_id: 0, entries: array![] };
    schedule(
        ref pending,
        10,
        1,
        0,
        caps::logic::track::legacy(0),
        Schedule {
            delay: 1,
            impact: DelayedImpact {
                kind: ImpactKind::Damage,
                selection: Selection::Row(0),
                relation: Relation::Any,
                amount: 4,
            },
        },
    );
    schedule(
        ref pending,
        10,
        1,
        0,
        caps::logic::track::legacy(0),
        Schedule {
            delay: 1,
            impact: DelayedImpact {
                kind: ImpactKind::Damage,
                selection: Selection::Row(4),
                relation: Relation::Any,
                amount: 4,
            },
        },
    );
    world.write_model_test(@pending);
    api
        .take_turn(
            id,
            array![
                caps::models::game::Action {
                    cap_id: 13, action_type: caps::models::game::ActionType::StackAbility(1),
                },
            ],
        );
    let stack = api.get_stack(id);
    assert!(
        stack.entries.len() == 1 && *stack.entries.at(0).id == 2, "selected older entry removed",
    );
    let record = api.get_turn(id, 0).unwrap();
    assert!(
        record.actions.len() == 1
            && record.stack_before.len() == 2
            && record.stack_after.len() == 1,
        "exact action journal",
    );
    assert!(record.energy_before == 5 && record.energy_after == 3, "ability paid once");
    assert!(record.before.len() == 14 && record.after.len() == 14, "before and after board");
    assert!(api.get_turn(id, 1).is_none(), "no fabricated future history");
}

#[test]
#[should_panic(expected: ("Pending effect missing", 'ENTRYPOINT_FAILED'))]
fn stale_stack_target_reverts() {
    let (mut world, api, id) = caps::tests::rules_test::setup();
    caps::tests::rules_test::put(ref world, 13, 0, 0);
    let mut game: caps::models::game::Game = world.read_model(id);
    game.energy = 5;
    world.write_model_test(@game);
    api
        .take_turn(
            id,
            array![
                caps::models::game::Action {
                    cap_id: 13, action_type: caps::models::game::ActionType::StackAbility(99),
                },
            ],
        );
}

#[test]
fn large_map_delayed_row_uses_map_height() {
    let mut stack = AbilityStack { game_id: 1, next_id: 0, entries: array![] };
    schedule(
        ref stack,
        1,
        0,
        0,
        caps::logic::track::legacy(4),
        Schedule {
            delay: 1,
            impact: DelayedImpact {
                kind: ImpactKind::Damage,
                selection: Selection::Row(8),
                relation: Relation::Any,
                amount: 4,
            },
        },
    );
    assert!(pop_ready(ref stack, 1).is_none(), "response turn remains");
    match pop_ready(ref stack, 2).unwrap().impact.selection {
        Selection::Row(row) => assert!(row == 8, "large row stored"),
        _ => panic!("wrong selection"),
    };
}

#[test]
#[should_panic(expected: ("Invalid row",))]
fn large_map_rejects_row_outside_board() {
    let mut stack = AbilityStack { game_id: 1, next_id: 0, entries: array![] };
    schedule(
        ref stack,
        1,
        0,
        0,
        caps::logic::track::legacy(4),
        Schedule {
            delay: 1,
            impact: DelayedImpact {
                kind: ImpactKind::Damage,
                selection: Selection::Row(9),
                relation: Relation::Any,
                amount: 4,
            },
        },
    );
}
