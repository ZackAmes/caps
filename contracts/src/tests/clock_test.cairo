use caps::models::cap::{Cap, Location};
use caps::models::game::{Action, ActionType, Game, Vec2};
use caps::systems::actions::IActionsDispatcherTrait;
use caps::tests::rules_test::{put, setup};
use dojo::model::{ModelStorage, ModelStorageTest};
use starknet::testing;

#[test]
fn clocks_charge_only_active_side_and_increment_once_per_turn() {
    testing::set_block_timestamp(1000);
    let (_, api, id) = setup();
    let (clock, now) = api.get_clock(id);
    assert!(clock.enabled && clock.p1_seconds == 120 && clock.p2_seconds == 120, "initial clocks");
    assert!(now == 1000 && clock.running_since == 1000, "creation starts clock");
    testing::set_block_timestamp(1030);
    api.take_turn(id, array![]);
    let (clock, _) = api.get_clock(id);
    assert!(
        clock.p1_seconds == 100 && clock.p2_seconds == 120, "thirty seconds plus ten increment",
    );
    testing::set_block_timestamp(1037);
    api.take_turn(id, array![]);
    let (clock, _) = api.get_clock(id);
    assert!(clock.p1_seconds == 100 && clock.p2_seconds == 123, "independent budgets");
    testing::set_block_timestamp(1136);
    api.take_turn(id, array![]);
    let (clock, _) = api.get_clock(id);
    assert!(clock.p1_seconds == 11 && clock.p2_seconds == 123, "one second remaining is valid");
}

#[test]
fn late_turn_loses_at_exact_zero_without_executing_actions() {
    testing::set_block_timestamp(1000);
    let (world, api, id) = setup();
    testing::set_block_timestamp(1120);
    api
        .take_turn(
            id, array![Action { cap_id: 5, action_type: ActionType::Play(Vec2 { x: 2, y: 0 }) }],
        );
    let (game, _) = api.get_game(id).unwrap();
    let cap: Cap = world.read_model(5);
    let (clock, _) = api.get_clock(id);
    assert!(
        game.over && game.winner_slot == 1 && game.turn_count == 1,
        "timeout advances terminal state",
    );
    assert!(cap.location == Location::Bench, "late action ignored");
    assert!(clock.p1_seconds == 0 && clock.timed_out_slot == 0, "no increment on loss");
}

#[test]
fn opponent_can_claim_second_player_timeout() {
    testing::set_block_timestamp(1000);
    let (_, api, _) = setup();
    let id = api.create_game_with_layout(0x456.try_into().unwrap(), 0);
    api.take_turn(id, array![]);
    testing::set_block_timestamp(1120);
    api.claim_timeout(id, 1);
    let (game, _) = api.get_game(id).unwrap();
    let (clock, _) = api.get_clock(id);
    assert!(
        game.over && game.winner_slot == 0 && game.winner == game.player1, "claim awards opponent",
    );
    assert!(
        clock.p2_seconds == 0 && clock.p1_seconds == 130 && clock.timed_out_slot == 1,
        "second slot loses",
    );
}

#[test]
#[should_panic(expected: ("Time remains", 'ENTRYPOINT_FAILED'))]
fn cannot_claim_before_expiry() {
    testing::set_block_timestamp(1000);
    let (_, api, id) = setup();
    testing::set_block_timestamp(1119);
    api.claim_timeout(id, 0);
}

#[test]
#[should_panic(expected: ("Only opponent may claim", 'ENTRYPOINT_FAILED'))]
fn active_player_cannot_claim_opponent_loss() {
    let (_, api, _) = setup();
    let id = api.create_game_with_layout(0x456.try_into().unwrap(), 0);
    testing::set_block_timestamp(9999);
    api.claim_timeout(id, 0);
}

#[test]
#[should_panic(expected: ("Stale turn", 'ENTRYPOINT_FAILED'))]
fn claim_cannot_cross_turn_boundary() {
    let (_, api, id) = setup();
    api.take_turn(id, array![]);
    testing::set_block_timestamp(9999);
    api.claim_timeout(id, 0);
}

#[test]
fn legacy_game_starts_fresh_and_goal_freezes_clock() {
    let (mut world, api, id) = setup();
    let (mut clock, _) = api.get_clock(id);
    clock.enabled = false;
    world.write_model_test(@clock);
    testing::set_block_timestamp(9999);
    api.take_turn(id, array![]);
    let (clock, _) = api.get_clock(id);
    assert!(
        clock.enabled && clock.p1_seconds == 130 && clock.p2_seconds == 120,
        "legacy clocks start on action",
    );
    put(ref world, 4, 3, 0);
    testing::set_block_timestamp(10019);
    api
        .take_turn(
            id, array![Action { cap_id: 4, action_type: ActionType::Move(Vec2 { x: 2, y: 0 }) }],
        );
    let game: Game = world.read_model(id);
    let (clock, _) = api.get_clock(id);
    assert!(
        game.over && clock.p2_seconds == 100 && clock.timed_out_slot == 2,
        "goal win charges time without increment",
    );
}
