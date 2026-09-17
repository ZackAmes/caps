use caps::systems::actions::IActionsDispatcherTrait;
use caps::models::board::{BoardDefinition, BoardSpot, BoardEdge, VisualPoint, BoardDistances};
use caps::models::game::{Vec2, Action, ActionType};
use caps::systems::boards::{IBoardsDispatcher, IBoardsDispatcherTrait};
use caps::tests::rules_test::setup;
use dojo::world::WorldStorageTrait;
use dojo::model::ModelStorage;

fn definition() -> BoardDefinition {
    BoardDefinition { name: "Permissionless map", width: 15, height: 15, view_width: 6000, view_height: 8000,
        p1_goal: Vec2 {x:0,y:0}, p2_goal: Vec2 {x:14,y:14},
        spots: array![
            BoardSpot { at: Vec2 {x:0,y:0}, position: VisualPoint {x:3000,y:1000}, energy:false },
            BoardSpot { at: Vec2 {x:9,y:7}, position: VisualPoint {x:1000,y:4000}, energy:true },
            BoardSpot { at: Vec2 {x:14,y:14}, position: VisualPoint {x:3000,y:7000}, energy:false },
        ], edges: array![BoardEdge {from:0,to:1,via:array![VisualPoint {x:2000,y:2000}]},BoardEdge {from:1,to:2,via:array![]}],
    }
}
#[test]
fn published_board_drives_game_and_preserves_art() {
    let (world, api, _) = setup();
    let (address, _) = world.dns(@"boards").unwrap();
    let registry = IBoardsDispatcher {contract_address:address};
    let board_id = registry.publish(definition());
    let board = registry.get_board(board_id).unwrap();
    assert!(board.creator == 0x123.try_into().unwrap(), "publisher needs no owner role");
    assert!(*board.definition.spots.at(1).position.x == 1000, "visual data preserved");
    let data: BoardDistances = world.read_model(board_id);
    let geometry = caps::logic::track::published(@board,@data);
    assert!(caps::logic::track::path_distance(geometry,Vec2{x:0,y:0},Vec2{x:14,y:14}) == Option::Some(2), "path ignores grid distance");
    let id = api.create_solo_game_with_board(board_id);
    assert!(api.get_game_board(id) == board_id, "immutable game binding");
    let (_, caps) = api.get_game(id).unwrap();
    let piece = *caps.at(0).id;
    api.take_turn(id,array![Action{cap_id:piece,action_type:ActionType::Play(Vec2{x:0,y:0})}]);
    api.take_turn(id,array![]);
    api.take_turn(id,array![Action{cap_id:piece,action_type:ActionType::Move(Vec2{x:9,y:7})}]);
    api.take_turn(id,array![]);
    api.take_turn(id,array![Action{cap_id:piece,action_type:ActionType::Move(Vec2{x:14,y:14})}]);
    let (game, _) = api.get_game(id).unwrap();
    assert!(game.over, "custom goal wins");
}
#[test]
#[should_panic(expected: ("Board must be connected", 'ENTRYPOINT_FAILED'))]
fn published_board_rejects_disconnected_graph() {
    let (world, _, _) = setup();
    let (address, _) = world.dns(@"boards").unwrap();
    let registry = IBoardsDispatcher {contract_address:address};
    let mut d=definition();d.edges=array![];
    registry.publish(d);
}
