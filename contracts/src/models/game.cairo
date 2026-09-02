#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Global {
    #[key]
    pub key: u8,
    pub games_counter: u64,
    pub cap_counter: u64,
    pub sets_counter: u64,
}

#[derive(Drop, Serde, Debug, Clone)]
#[dojo::model]
pub struct Game {
    #[key]
    pub id: u64,
    pub player1: felt252,
    pub player2: felt252,
    pub layout: u8,
    /// Which set contract defines the pieces for this game.
    pub set_id: u64,
    pub turn_count: u64,
    pub over: bool,
    pub winner: felt252,
    pub caps_ids: Array<u64>,
    /// Effect ids currently live in this game.
    pub effect_ids: Array<u64>,
    /// Energy the current turn player has remaining this turn.
    pub energy: u8,
    pub last_action_timestamp: u64,
}

#[derive(Drop, Serde, Copy, Introspect)]
pub struct Action {
    pub cap_id: u64,
    pub action_type: ActionType,
}

#[derive(Drop, Serde, Copy, Introspect)]
pub enum ActionType {
    /// Deploy a bench cap at a position (must be the player's deploy spot).
    Play: Vec2,
    /// Move 1 step. Moving onto an enemy tile attacks it: if it dies the
    /// mover takes the tile, otherwise the mover stays put.
    Move: Vec2,
    /// Claim a capture: sends a fully-surrounded enemy cap at `Vec2`
    /// back to bench at full health.
    ClaimCapture: Vec2,
    /// Activate the acting cap's ability at `Vec2` (validated by the core,
    /// executed by the set contract, ops applied by the core).
    Ability: Vec2,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Debug, Introspect)]
pub struct Vec2 {
    pub x: u8,
    pub y: u8,
}
