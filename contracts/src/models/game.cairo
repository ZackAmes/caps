#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Global {
    #[key]
    pub key: u8,
    pub games_counter: u64,
    pub cap_counter: u64,
}

#[derive(Drop, Serde, Debug, Clone)]
#[dojo::model]
pub struct Game {
    #[key]
    pub id: u64,
    pub player1: felt252,
    pub player2: felt252,
    pub layout: u8,
    pub turn_count: u64,
    pub over: bool,
    pub winner: felt252,
    pub caps_ids: Array<u64>,
    pub last_action_timestamp: u64,
}

#[derive(Drop, Serde, Copy, Introspect)]
pub struct Action {
    pub cap_id: u64,
    pub action_type: ActionType,
}

#[derive(Drop, Serde, Copy, Introspect)]
pub enum ActionType {
    Play: Vec2,
    Move: Vec2,
    Attack: Vec2,
    /// Claim a capture: sends a fully-surrounded enemy cap at `Vec2` back to bench.
    ClaimCapture: Vec2,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Debug, Introspect)]
pub struct Vec2 {
    pub x: u8,
    pub y: u8,
}
