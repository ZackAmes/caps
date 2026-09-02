use caps::models::game::Vec2;

/// A cap (piece) on the board or bench.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Cap {
    #[key]
    pub id: u64,
    pub owner: felt252,
    /// Piece type id within the game's set.
    pub cap_type: u16,
    /// Which set contract defines this piece.
    pub set_id: u64,
    /// Bench, Board(Vec2), or Dead.
    pub location: Location,
    pub health: u16,
    /// Absorbs damage before health. Granted by Shield ops/effects.
    pub shield: u16,
    /// Turns remaining on the cap's stun.
    pub stunned_turns: u8,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Debug, Introspect)]
pub enum Location {
    #[default]
    Bench,
    Board: Vec2,
    Dead,
}

/// Chebyshev distance between two cells (for adjacency & range checks).
pub fn dist(a: Vec2, b: Vec2) -> u32 {
    let dx: u32 = if a.x > b.x { (a.x - b.x).into() } else { (b.x - a.x).into() };
    let dy: u32 = if a.y > b.y { (a.y - b.y).into() } else { (b.y - a.y).into() };
    if dx > dy { dx } else { dy }
}

/// Get board position if on board.
pub fn get_position(cap: @Cap) -> Option<Vec2> {
    match (*cap).location {
        Location::Board(v) => Option::Some(v),
        _ => Option::None,
    }
}

/// Is this cap on the board (not bench, not dead)?
pub fn is_on_board(cap: @Cap) -> bool {
    match (*cap).location {
        Location::Board(_) => true,
        _ => false,
    }
}
