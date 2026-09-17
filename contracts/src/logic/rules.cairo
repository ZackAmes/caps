use caps::logic::track::BoardGeometry;
use caps::logic::track::energy_space;
use caps::logic::track::{get_p1_deploy_spot, get_p2_deploy_spot, get_walkable_neighbors};
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

pub fn is_surrounded(caps: @Array<Cap>, layout: BoardGeometry, pos: Vec2) -> bool {
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

pub fn is_goal(cap: Cap, layout: BoardGeometry) -> bool {
    match cap.location {
        Location::Board(p) => p == (if cap.player_slot == 0 {
            get_p2_deploy_spot(layout)
        } else {
            get_p1_deploy_spot(layout)
        }),
        _ => false,
    }
}

pub fn objective_income(caps: @Array<Cap>, slot: u8, layout: BoardGeometry) -> u8 {
    let mut income = 0;
    for c in caps.span() {
        if *c.player_slot == slot {
            if let Location::Board(p) = c.location {
                if energy_space(layout, *p) {
                    income += 1;
                }
            }
        }
    }
    income
}

pub fn add_energy(stored: u8, income: u16) -> u8 {
    let total: u32 = stored.into() + income.into();
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
