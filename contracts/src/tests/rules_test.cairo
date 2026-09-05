use caps::models::cap::{Cap, Location, m_Cap};
use caps::models::effect::m_Effect;
use caps::models::game::{Action, ActionType, Game, Hand, Vec2, m_Game, m_Global, m_Hand};
use caps::models::set::m_Set;
use caps::sets::set_zero::set_zero;
use caps::systems::actions::{IActionsDispatcher, IActionsDispatcherTrait, actions};
use dojo::model::{ModelStorage, ModelStorageTest};
use dojo::world::{WorldStorage, WorldStorageTrait, world};
use dojo_cairo_test::{
    ContractDefTrait, NamespaceDef, TestResource, WorldStorageTestTrait, spawn_test_world,
};
use starknet::{ContractAddress, testing};

fn setup() -> (WorldStorage, IActionsDispatcher, u64) {
    let ns = NamespaceDef {
        namespace: "caps",
        resources: [
            TestResource::Model(m_Game::TEST_CLASS_HASH),
            TestResource::Model(m_Hand::TEST_CLASS_HASH),
            TestResource::Model(m_Global::TEST_CLASS_HASH),
            TestResource::Model(m_Cap::TEST_CLASS_HASH),
            TestResource::Model(m_Effect::TEST_CLASS_HASH),
            TestResource::Model(m_Set::TEST_CLASS_HASH),
            TestResource::Contract(actions::TEST_CLASS_HASH),
            TestResource::Contract(set_zero::TEST_CLASS_HASH),
        ]
            .span(),
    };
    let world = spawn_test_world(world::TEST_CLASS_HASH, [ns].span());
    world
        .sync_perms_and_inits(
            [
                ContractDefTrait::new(@"caps", @"actions")
                    .with_writer_of([dojo::utils::bytearray_hash(@"caps")].span())
            ]
                .span(),
        );
    let (address, _) = world.dns(@"actions").unwrap();
    let (set_address, _) = world.dns(@"set_zero").unwrap();
    let api = IActionsDispatcher { contract_address: address };
    api.register_set(set_address, 12, 6, 16);
    // The caller of dispatched calls is the test contract itself.
    let caller: ContractAddress = 0x123.try_into().unwrap();
    testing::set_contract_address(caller);
    let id = api.create_solo_game();
    (world, api, id)
}

fn put(ref world: WorldStorage, id: u64, x: u8, y: u8) {
    let mut c: Cap = world.read_model(id);
    c.location = Location::Board(Vec2 { x, y });
    world.write_model_test(@c);
}

fn act(id: u64, kind: ActionType) -> Action {
    Action { cap_id: id, action_type: kind }
}

#[test]
fn initial_hand_and_free_deployment() {
    let (world, api, id) = setup();
    let (game, caps) = api.get_game(id).unwrap();
    assert!(game.energy == 1 && !game.over && caps.len() == 12, "initial state");
    assert!(*caps.at(0).player_slot == 0 && *caps.at(1).player_slot == 1, "solo identities");
    let (_, before) = api.get_hand(id, 0).unwrap();
    assert!(before == array![1, 3, 5, 7].span(), "initial deterministic hand");
    api.take_turn(id, array![act(5, ActionType::Play(Vec2 { x: 2, y: 0 }))]);
    let (_, after) = api.get_hand(id, 0).unwrap();
    assert!(after == array![1, 3, 7, 9].span(), "played choice removed and refilled");
    let (game, _) = api.get_game(id).unwrap();
    assert!(
        game.p1_energy == 1 && game.energy == 1 && game.turn_count == 1,
        "free deploy and next budget",
    );
    let cap: Cap = world.read_model(5);
    assert!(cap.location == Location::Board(Vec2 { x: 2, y: 0 }), "deployed");
}

#[test]
#[should_panic(expected: ("No actions remaining", 'ENTRYPOINT_FAILED'))]
fn cannot_move_twice_without_bonus() {
    let (mut world, api, id) = setup();
    put(ref world, 3, 2, 0);
    api
        .take_turn(
            id,
            array![
                act(3, ActionType::Move(Vec2 { x: 3, y: 0 })),
                act(3, ActionType::Move(Vec2 { x: 4, y: 0 })),
            ],
        );
}

#[test]
fn runner_bonus_reads_updated_position_and_expires() {
    let (mut world, api, id) = setup();
    put(ref world, 11, 0, 0);
    let mut game: Game = world.read_model(id);
    game.energy = 3;
    game.p1_energy = 3;
    world.write_model_test(@game);
    api
        .take_turn(
            id,
            array![
                act(11, ActionType::Move(Vec2 { x: 1, y: 0 })),
                act(11, ActionType::Ability(Vec2 { x: 1, y: 0 })),
                act(11, ActionType::Move(Vec2 { x: 2, y: 0 })),
            ],
        );
    let cap: Cap = world.read_model(11);
    assert!(cap.location == Location::Board(Vec2 { x: 2, y: 0 }), "bonus move used updated board");
    let game: Game = world.read_model(id);
    assert!(game.p1_energy == 1, "only ability costs energy");
}

#[test]
fn capture_is_automatic_and_blocks_two_owner_turns() {
    let (mut world, api, id) = setup();
    put(ref world, 4, 0, 0); // enemy Guardian in corner
    put(ref world, 3, 1, 0);
    put(ref world, 5, 0, 2);
    api.take_turn(id, array![act(5, ActionType::Move(Vec2 { x: 0, y: 1 }))]);
    let c: Cap = world.read_model(4);
    assert!(
        c.location == Location::Bench && c.available_turn == 5 && c.health == 6, "capture cooldown",
    );
    let (_, h1) = api.get_hand(id, 1).unwrap();
    for c in h1 {
        assert!(*c != 4, "not eligible first turn");
    }
    api.take_turn(id, array![]);
    api.take_turn(id, array![]);
    let (_, h2) = api.get_hand(id, 1).unwrap();
    for c in h2 {
        assert!(*c != 4, "not eligible second turn");
    }
    api.take_turn(id, array![]);
    api.take_turn(id, array![]);
    let c: Cap = world.read_model(4);
    let game: Game = world.read_model(id);
    assert!(c.available_turn == game.turn_count, "eligible third owner turn");
    let hand: Hand = world.read_model((id, 1_u8));
    assert!(*hand.roster.at(5) == 4, "capture goes to back of queue");
}

#[test]
fn reaching_opponent_goal_wins_without_towers() {
    let (mut world, api, id) = setup();
    put(ref world, 3, 1, 4);
    api.take_turn(id, array![act(3, ActionType::Move(Vec2 { x: 2, y: 4 }))]);
    let game: Game = world.read_model(id);
    assert!(game.over && game.winner_slot == 0 && game.winner == game.player1, "goal win");
}

#[test]
fn p2_goal_is_opposite_even_in_solo() {
    let (mut world, api, id) = setup();
    api.take_turn(id, array![]);
    put(ref world, 4, 3, 0);
    api.take_turn(id, array![act(4, ActionType::Move(Vec2 { x: 2, y: 0 }))]);
    let game: Game = world.read_model(id);
    assert!(game.over && game.winner_slot == 1, "p2 goal");
}

#[test]
fn income_is_owner_scoped_and_capped() {
    let (mut world, api, id) = setup();
    put(ref world, 1, 0, 2); // generator + objective = 2 extra income
    put(ref world, 3, 4, 2); // second objective
    api.take_turn(id, array![]);
    let game: Game = world.read_model(id);
    assert!(game.energy == 1, "enemy gets base only");
    api.take_turn(id, array![]);
    let game: Game = world.read_model(id);
    assert!(game.energy == 5, "stored 1 + base 1 + objectives 2 + generator 1");
    api.take_turn(id, array![]);
    api.take_turn(id, array![]);
    let game: Game = world.read_model(id);
    assert!(game.energy == 5, "energy capped");
}

#[test]
fn combat_and_ability_targeting_work_in_solo_both_directions() {
    let (mut world, api, id) = setup();
    put(ref world, 3, 4, 1);
    put(ref world, 6, 4, 0);
    let mut game: Game = world.read_model(id);
    game.energy = 3;
    world.write_model_test(@game);
    api
        .take_turn(
            id,
            array![
                act(3, ActionType::Ability(Vec2 { x: 4, y: 0 })),
                act(3, ActionType::Move(Vec2 { x: 4, y: 0 })),
            ],
        );
    let c: Cap = world.read_model(6);
    assert!(c.health == 6, "ability and combat damage persist");
    let c: Cap = world.read_model(3);
    assert!(c.location == Location::Board(Vec2 { x: 4, y: 1 }), "survivor blocks attacker");
}

#[test]
fn hand_skips_dead_and_board_slots_without_stalling() {
    let (mut world, api, id) = setup();
    for cap_id in array![1_u64, 3, 5, 7].span() {
        let mut c: Cap = world.read_model(*cap_id);
        c.location = Location::Dead;
        c.health = 0;
        world.write_model_test(@c);
    }
    let (_, hand) = api.get_hand(id, 0).unwrap();
    assert!(hand == array![9, 11].span(), "remaining bench pieces accessible");
}

#[test]
#[should_panic(expected: ("Not your cap", 'ENTRYPOINT_FAILED'))]
fn solo_cannot_act_with_opposing_piece() {
    let (mut world, api, id) = setup();
    put(ref world, 4, 0, 0);
    api.take_turn(id, array![act(4, ActionType::Move(Vec2 { x: 1, y: 0 }))]);
}

#[test]
#[should_panic(expected: ("Ability already used", 'ENTRYPOINT_FAILED'))]
fn bonus_ability_cannot_repeat_in_same_turn() {
    let (mut world, api, id) = setup();
    put(ref world, 11, 0, 0);
    let mut game: Game = world.read_model(id);
    game.energy = 5;
    world.write_model_test(@game);
    api
        .take_turn(
            id,
            array![
                act(11, ActionType::Ability(Vec2 { x: 0, y: 0 })),
                act(11, ActionType::Ability(Vec2 { x: 0, y: 0 })),
            ],
        );
}

#[test]
#[should_panic(expected: ("No actions remaining", 'ENTRYPOINT_FAILED'))]
fn bonus_move_cannot_be_spent_on_deployment() {
    let (mut world, api, id) = setup();
    put(ref world, 11, 0, 0);
    let mut game: Game = world.read_model(id);
    game.energy = 5;
    world.write_model_test(@game);
    api
        .take_turn(
            id,
            array![
                act(11, ActionType::Move(Vec2 { x: 1, y: 0 })),
                act(11, ActionType::Ability(Vec2 { x: 1, y: 0 })),
                act(3, ActionType::Play(Vec2 { x: 2, y: 0 })),
            ],
        );
}

#[test]
fn ability_triggers_automatic_capture_too() {
    let (mut world, api, id) = setup();
    put(ref world, 4, 0, 0);
    put(ref world, 5, 1, 0);
    put(ref world, 7, 0, 1);
    let mut game: Game = world.read_model(id);
    game.energy = 3;
    world.write_model_test(@game);
    api.take_turn(id, array![act(5, ActionType::Ability(Vec2 { x: 0, y: 1 }))]);
    let captured: Cap = world.read_model(4);
    assert!(captured.location == Location::Bench, "ability resolves capture");
    let shielded: Cap = world.read_model(7);
    assert!(shielded.shield == 3, "friendly targeting");
}

#[test]
fn own_turn_capture_skips_next_two_owner_turns() {
    assert!(caps::logic::rules::capture_ready_turn(0, 0) == 6, "own capture eligibility");
    assert!(caps::logic::rules::capture_ready_turn(1, 1) == 7, "p2 own capture eligibility");
    assert!(caps::logic::rules::capture_ready_turn(1, 0) == 6, "opponent capture eligibility");
}

#[test]
fn general_bonus_can_deploy_but_move_bonus_is_preserved() {
    let mut actions: u8 = 2;
    let mut moves: u8 = 1;
    caps::logic::rules::spend_action(ref actions, ref moves, false);
    assert!(actions == 1 && moves == 1, "general action deployed");
    caps::logic::rules::spend_action(ref actions, ref moves, true);
    assert!(actions == 1 && moves == 0, "bonus movement spent first");
}

#[test]
fn winning_attack_takes_the_goal_square() {
    let (mut world, api, id) = setup();
    put(ref world, 3, 1, 4);
    put(ref world, 4, 2, 4);
    let mut defender: Cap = world.read_model(4);
    defender.health = 1;
    world.write_model_test(@defender);
    api.take_turn(id, array![act(3, ActionType::Move(Vec2 { x: 2, y: 4 }))]);
    let game: Game = world.read_model(id);
    assert!(game.over && game.winner_slot == 0, "arrival wins");
}
