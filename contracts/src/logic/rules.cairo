use caps::logic::track::get_walkable_neighbors;
use caps::models::cap::{Cap, Location};
use caps::models::game::Vec2;

pub const ENERGY_CAP: u8 = 5;
pub const BASE_INCOME: u8 = 1;

pub fn index_at(caps: @Array<Cap>, pos: Vec2) -> usize {
    for i in 0..caps.len() {
        if let Location::Board(p) = caps.at(i).location {
            if *p == pos {
                return i;
            }
        }
    }
    caps.len()
}

pub fn is_surrounded(caps: @Array<Cap>, layout: u8, pos: Vec2) -> bool {
    let idx = index_at(caps, pos);
    if idx == caps.len() {
        return false;
    }
    let neighbors = get_walkable_neighbors(layout, pos);
    if neighbors.is_empty() {
        return false;
    }
    for p in neighbors.span() {
        let n = index_at(caps, *p);
        if n == caps.len() || caps.at(n).player_slot == caps.at(idx).player_slot {
            return false;
        }
    }
    true
}

pub fn capture_ready_turn(turn: u64, slot: u8) -> u64 {
    // Skip the next two complete owner turns, even if captured during its own turn.
    turn + (if turn % 2 == slot.into() {
        6
    } else {
        5
    })
}

pub fn is_goal(cap: Cap) -> bool {
    match cap.location {
        Location::Board(p) => p.x == 2 && p.y == (if cap.player_slot == 0 {
            4
        } else {
            0
        }),
        _ => false,
    }
}

pub fn objective_income(caps: @Array<Cap>, slot: u8) -> u8 {
    let mut income = 0;
    for c in caps.span() {
        if *c.player_slot == slot {
            if let Location::Board(p) = c.location {
                if *p.y == 2 && (*p.x == 0 || *p.x == 4) {
                    income += 1;
                }
            }
        }
    }
    income
}

pub fn add_energy(stored: u8, income: u16) -> u8 {
    let total: u16 = stored.into() + income;
    if total > ENERGY_CAP.into() {
        ENERGY_CAP
    } else {
        total.try_into().unwrap()
    }
}

/// Move-only bonuses are consumed first, preserving general actions for deployment.
pub fn spend_action(ref actions: u8, ref moves: u8, is_move: bool) {
    if is_move && moves > 0 {
        moves -= 1;
    } else {
        assert!(actions > 0, "No actions remaining");
        actions -= 1;
    }
}
