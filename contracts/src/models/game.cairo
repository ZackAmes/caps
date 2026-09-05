#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Global {
    #[key]
    pub key: u8,
    pub games_counter: u64,
    pub cap_counter: u64,
    pub sets_counter: u64,
}

/// Public deterministic draw queue. Eligible bench pieces fill the hand in order.
#[derive(Drop, Serde, Debug, Clone)]
#[dojo::model]
pub struct Hand {
    #[key]
    pub game_id: u64,
    /// 0 = player1's hand, 1 = player2's hand.
    #[key]
    pub player_slot: u8,
    /// Queue order. Played/captured pieces move to the back.
    pub roster: Array<u64>,
    /// Maximum number of eligible bench pieces in hand.
    pub hand_size: u8,
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
    /// 0/1 for a winner, 2 while no side has won.
    pub winner_slot: u8,
    pub caps_ids: Array<u64>,
    /// Effect ids currently live in this game.
    pub effect_ids: Array<u64>,
    /// Prepared budget for the current player, including this turn's income.
    pub energy: u8,
    pub p1_energy: u8,
    pub p2_energy: u8,
    pub next_effect_id: u64,
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
    /// The cap must be in the player's current hand window.
    Play: Vec2,
    /// Move 1 step. Moving onto an enemy tile attacks it: if it dies the
    /// mover takes the tile, otherwise the mover stays put.
    Move: Vec2,
    /// Activate the acting cap's ability at `Vec2` (validated by the core,
    /// executed by the set contract, ops applied by the core).
    Ability: Vec2,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Debug, Introspect)]
pub struct Vec2 {
    pub x: u8,
    pub y: u8,
}
