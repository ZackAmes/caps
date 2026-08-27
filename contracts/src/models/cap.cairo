use caps::models::game::{Vec2};

/// A cap (piece) on the board or bench.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Cap {
    #[key]
    pub id: u64,
    pub owner: felt252,
    pub cap_type: u8,
    /// Bench, Board(Vec2), or Dead.
    pub location: Location,
    pub health: u16,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Debug, Introspect)]
pub enum Location {
    #[default]
    Bench,
    Board: Vec2,
    Dead,
}

/// Simple static per-type stats: (max_health, attack, attack_range, move_range).
/// Type 0 is the tower; 1-3 are basic units.
pub fn cap_stats(cap_type: u8) -> (u16, u16, u8, u8) {
    match cap_type {
        0 => (12, 2, 1, 1), // Tower: tanky, short range
        1 => (8, 2, 1, 1),  // Knight: balanced
        2 => (8, 3, 1, 2),  // Archer: longer attack range
        3 => (6, 3, 2, 1),  // Assassin: longer move range
        _ => (8, 2, 1, 1),
    }
}

pub fn is_tower(cap_type: u8) -> bool {
    cap_type == 0
}

/// Chebyshev distance between two cells (for attack range & diagonal steps).
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
