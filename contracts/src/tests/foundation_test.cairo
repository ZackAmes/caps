use caps::logic::passives::{bonus, condition_met, is_active};
use caps::logic::rules::{is_goal, objective_income};
use caps::logic::track::{
    get_board_dimensions, get_walkable_neighbors, is_valid_step, path_distance,
};
use caps::models::cap::{Cap, Location};
use caps::models::effect::{Condition, Passive, PassiveKind, PassiveTarget, Relation};
use caps::models::game::{Action, ActionType, Game, Vec2};
use caps::models::set::Set;
use caps::models::set_data::CapType;
use caps::systems::actions::IActionsDispatcherTrait;
use dojo::model::{ModelStorage, ModelStorageTest};
use dojo::world::WorldStorageTrait;

fn piece(id: u64, slot: u8, x: u8, y: u8) -> Cap {
    Cap {
        id,
        owner: 0x123,
        player_slot: slot,
        cap_type: id.try_into().unwrap(),
        set_id: 0,
        location: Location::Board(Vec2 { x, y }),
        health: 10,
        shield: 0,
        stunned_turns: 0,
        available_turn: 0,
    }
}
fn passive(conditions: Span<Condition>) -> Passive {
    Passive {
        kind: PassiveKind::AttackBonus, amount: 3, target: PassiveTarget::SelfCap, conditions,
    }
}
fn definition(id: u16, passives: Array<Passive>) -> CapType {
    let mut def = caps::sets::set_zero::cap_type_of(1).unwrap();
    def.id = id;
    def.max_health = 20;
    def.passives = passives;
    def
}
#[test]
fn path_edges_not_grid_proximity() {
    assert!(
        path_distance(caps::logic::track::legacy(0), Vec2 { x: 1, y: 0 }, Vec2 { x: 0, y: 1 }) == Option::Some(2),
        "no corner cut",
    );
    assert!(
        path_distance(caps::logic::track::legacy(0), Vec2 { x: 2, y: 0 }, Vec2 { x: 2, y: 4 }) == Option::Some(8),
        "perimeter range",
    );
    assert!(
        path_distance(caps::logic::track::legacy(1), Vec2 { x: 2, y: 0 }, Vec2 { x: 2, y: 4 }) == Option::Some(4),
        "cross range",
    );
    assert!(is_valid_step(caps::logic::track::legacy(2), Vec2 { x: 0, y: 0 }, Vec2 { x: 1, y: 1 }), "diagonal edge");
    assert!(
        path_distance(caps::logic::track::legacy(3), Vec2 { x: 2, y: 0 }, Vec2 { x: 3, y: 2 }) == Option::Some(2),
        "diamond junction",
    );
    assert!(path_distance(caps::logic::track::legacy(0), Vec2 { x: 1, y: 1 }, Vec2 { x: 1, y: 1 }).is_none(), "invalid tile");
}
#[test]
fn row_conditions_and_board_lifetime() {
    let mut source = piece(1, 0, 1, 0);
    let ally = piece(2, 0, 3, 0);
    let enemy = piece(3, 1, 4, 0);
    let p = passive(array![Condition::PieceInRow(Relation::Ally)].span());
    assert!(!is_active(p, source, 20, @array![source, enemy], caps::logic::track::legacy(0)), "self and enemy excluded");
    assert!(is_active(p, source, 20, @array![source, ally, enemy], caps::logic::track::legacy(0)), "ally activates");
    source.stunned_turns = 1;
    assert!(
        is_active(p, source, 20, @array![source, ally], caps::logic::track::legacy(0)), "stun does not disable board traits",
    );
    source.location = Location::Bench;
    assert!(
        !is_active(passive(array![].span()), source, 20, @array![source, ally], caps::logic::track::legacy(0)),
        "bench is inactive",
    );
    source.location = Location::Dead;
    assert!(
        !is_active(passive(array![].span()), source, 20, @array![source, ally], caps::logic::track::legacy(0)),
        "dead is inactive",
    );
}
#[test]
fn conditions_are_conjunctive_and_health_is_percentage() {
    let mut source = piece(1, 0, 1, 0);
    let ally = piece(2, 0, 0, 1);
    assert!(
        !condition_met(Condition::AllyWithin(1), source, 20, @array![source, ally], caps::logic::track::legacy(0)),
        "path adjacency",
    );
    let p = passive(array![Condition::AllyWithin(2), Condition::HealthBelowPercent(50)].span());
    assert!(!is_active(p, source, 20, @array![source, ally], caps::logic::track::legacy(0)), "strictly below threshold");
    source.health = 9;
    assert!(is_active(p, source, 20, @array![source, ally], caps::logic::track::legacy(0)), "all conditions met");
}
#[test]
fn auras_derive_from_current_board_and_stack() {
    let a = piece(1, 0, 0, 0);
    let mut b = piece(2, 0, 1, 0);
    let mut c = piece(3, 0, 0, 1);
    let mut p = passive(array![].span());
    p.target = PassiveTarget::AlliesWithin(1);
    let mut p2 = p;
    p2.target = PassiveTarget::AlliesWithin(2);
    let defs = array![definition(1, array![p]), definition(2, array![]), definition(3, array![p2])];
    assert!(
        bonus(PassiveKind::AttackBonus, b, @array![a, b, c], @defs, caps::logic::track::legacy(0)) == 6, "additive stacking",
    );
    c.location = Location::Bench;
    assert!(bonus(PassiveKind::AttackBonus, b, @array![a, b, c], @defs, caps::logic::track::legacy(0)) == 3, "removed source");
    b.location = Location::Board(Vec2 { x: 2, y: 0 });
    assert!(bonus(PassiveKind::AttackBonus, b, @array![a, b, c], @defs, caps::logic::track::legacy(0)) == 0, "left radius");
}

/// Test-only set: exercises the framework without changing the playable roster.
#[dojo::contract]
pub mod passive_test_set {
    use caps::models::effect::{Condition, Passive, PassiveKind, PassiveTarget, Relation};
    use caps::models::game::Vec2;
    use caps::models::set::ISetInterface;
    use caps::models::set_data::{AbilityContext, CapType, SetOutput};
    #[abi(embed_v0)]
    impl Impl of ISetInterface<ContractState> {
        fn get_cap_type(self: @ContractState, id: u16) -> Option<CapType> {
            let mut def = caps::sets::set_zero::cap_type_of(id).unwrap();
            if id == 5 {
                def
                    .passives =
                        array![
                            Passive {
                                kind: PassiveKind::AttackBonus,
                                amount: 3,
                                target: PassiveTarget::SelfCap,
                                conditions: array![Condition::PieceInRow(Relation::Ally)].span(),
                            },
                        ];
            }
            if id == 0 {
                def
                    .passives =
                        array![
                            Passive {
                                kind: PassiveKind::DamageReduction,
                                amount: 2,
                                target: PassiveTarget::AlliesWithin(1),
                                conditions: array![].span(),
                            },
                        ];
            }
            Option::Some(def)
        }
        fn activate_stack_ability(
            self: @ContractState, ctx: AbilityContext, target_id: u64,
        ) -> SetOutput {
            caps::sets::set_zero::use_stack_ability(ctx, target_id)
        }

        fn activate_ability(self: @ContractState, ctx: AbilityContext, target: Vec2) -> SetOutput {
            caps::sets::set_zero::use_ability(ctx, target)
        }
    }
}

#[test]
fn queued_move_removes_bonus_before_contact_attack() {
    let (mut world, api, id) = caps::tests::rules_test::setup();
    let (address, _) = world.dns(@"passive_test_set").unwrap();
    let mut set: Set = world.read_model(0_u64);
    set.address = address;
    world.write_model_test(@set);
    caps::tests::rules_test::put(ref world, 11, 1, 4);
    caps::tests::rules_test::put(ref world, 3, 0, 4);
    caps::tests::rules_test::put(ref world, 4, 2, 4);
    let mut game: Game = world.read_model(id);
    game.energy = 3;
    world.write_model_test(@game);
    api
        .take_turn(
            id,
            array![
                Action { cap_id: 11, action_type: ActionType::Ability(Vec2 { x: 1, y: 4 }) },
                Action { cap_id: 3, action_type: ActionType::Move(Vec2 { x: 0, y: 3 }) },
                Action { cap_id: 11, action_type: ActionType::Move(Vec2 { x: 2, y: 4 }) },
            ],
        );
    let target: Cap = world.read_model(4_u64);
    assert!(target.health == 4, "bonus must disappear within the queued turn");
}

#[test]
fn live_aura_reduces_active_ability_damage() {
    let (mut world, api, id) = caps::tests::rules_test::setup();
    let (address, _) = world.dns(@"passive_test_set").unwrap();
    let mut set: Set = world.read_model(0_u64);
    set.address = address;
    world.write_model_test(@set);
    caps::tests::rules_test::put(ref world, 3, 0, 1);
    caps::tests::rules_test::put(ref world, 4, 0, 0);
    caps::tests::rules_test::put(ref world, 2, 1, 0);
    let mut game: Game = world.read_model(id);
    game.energy = 3;
    world.write_model_test(@game);
    api
        .take_turn(
            id, array![Action { cap_id: 3, action_type: ActionType::Ability(Vec2 { x: 0, y: 0 }) }],
        );
    let target: Cap = world.read_model(4_u64);
    assert!(target.health == 6, "aura applies to ability damage, not only contact");
}

#[test]
fn passive_stacking_saturates_without_overflowing_energy_cap() {
    let c = piece(1, 0, 1, 0);
    let mut p = passive(array![].span());
    p.amount = 65535;
    let defs = array![definition(1, array![p, p])];
    assert!(bonus(PassiveKind::AttackBonus, c, @array![c], @defs, caps::logic::track::legacy(0)) == 65535, "saturating bonus");
    assert!(caps::logic::rules::add_energy(5, 65535) == 5, "energy cap does not overflow");
}

#[test]
fn large_map_geometry_income_and_enemy_half() {
    assert!(get_board_dimensions(caps::logic::track::legacy(4)) == (7, 9), "larger dimensions");
    assert!(get_board_dimensions(caps::logic::track::legacy(0)) == (5, 5), "old dimensions");
    assert!(
        path_distance(caps::logic::track::legacy(4), Vec2 { x: 3, y: 0 }, Vec2 { x: 3, y: 2 }) == Option::Some(1),
        "explicit edge",
    );
    assert!(path_distance(caps::logic::track::legacy(4), Vec2 { x: 0, y: 0 }, Vec2 { x: 0, y: 0 }).is_none(), "void node");
    assert!(get_walkable_neighbors(caps::logic::track::legacy(4), Vec2 { x: 7, y: 0 }).is_empty(), "outside board");
    assert!(get_walkable_neighbors(caps::logic::track::legacy(99), Vec2 { x: 0, y: 0 }).is_empty(), "unknown board");
    let energy_piece = piece(1, 0, 0, 4);
    assert!(objective_income(@array![energy_piece], 0, caps::logic::track::legacy(4)) == 1, "map energy");
    assert!(!is_goal(energy_piece, caps::logic::track::legacy(4)), "old goal not reused");
    assert!(is_goal(piece(2, 1, 3, 0), caps::logic::track::legacy(4)), "p2 goal");
    assert!(
        !condition_met(Condition::OnEnemyHalf, piece(3, 0, 0, 3), 20, @array![], caps::logic::track::legacy(4)), "own half",
    );
    assert!(
        condition_met(Condition::OnEnemyHalf, piece(3, 0, 0, 5), 20, @array![], caps::logic::track::legacy(4)), "enemy half",
    );
}
