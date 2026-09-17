use caps::models::game::Vec2;
use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, Debug, Introspect, DojoStore)]
pub struct VisualPoint { pub x: u16, pub y: u16 }
#[derive(Copy, Drop, Serde, Debug, Introspect, DojoStore)]
pub struct BoardSpot { pub at: Vec2, pub position: VisualPoint, pub energy: bool }
#[derive(Drop, Serde, Debug, Introspect, DojoStore)]
pub struct BoardEdge { pub from: u8, pub to: u8, pub via: Array<VisualPoint> }
#[derive(Drop, Serde, Debug, Introspect, DojoStore)]
pub struct BoardDefinition {
    pub name: ByteArray,
    pub width: u8,
    pub height: u8,
    /// Visual units are thousandths; independent of logical grid coordinates.
    pub view_width: u16,
    pub view_height: u16,
    pub p1_goal: Vec2,
    pub p2_goal: Vec2,
    pub spots: Array<BoardSpot>,
    pub edges: Array<BoardEdge>,
}
#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct PublishedBoard {
    #[key] pub id: u64,
    pub creator: ContractAddress,
    pub definition: BoardDefinition,
}
#[derive(Drop, Serde)]
#[dojo::model]
pub struct BoardDistances { #[key] pub id: u64, pub packed: Array<u128> }
#[derive(Copy, Drop, Serde)]
#[dojo::model]
pub struct BoardRegistry { #[key] pub id: u8, pub count: u64 }
#[derive(Copy, Drop, Serde)]
#[dojo::model]
pub struct GameBoard { #[key] pub game_id: u64, pub board_id: u64 }

#[derive(Copy, Drop, Serde)]
#[dojo::model]
pub struct BoardPublication { #[key] pub transaction: felt252, pub board_id: u64 }
