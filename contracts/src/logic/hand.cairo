use caps::models::cap::{Cap, Location};
use caps::models::game::Hand;

pub const HAND_SIZE: u8 = 4;

/// Skip board, dead and cooling pieces, rather than blocking the draw queue.
pub fn window_ids(hand: @Hand, caps: @Array<Cap>, turn_count: u64) -> Array<u64> {
    let mut out = array![];
    for id in hand.roster.span() {
        for c in caps.span() {
            if c.id == id
                && *c.location == Location::Bench
                && *c.available_turn <= turn_count
                && out.len() < (*hand.hand_size).into() {
                out.append(*id);
            }
        };
    }
    out
}

pub fn is_in_hand(hand: @Hand, caps: @Array<Cap>, turn_count: u64, cap_id: u64) -> bool {
    let ids = window_ids(hand, caps, turn_count);
    for id in ids.span() {
        if *id == cap_id {
            return true;
        }
    }
    false
}

pub fn requeue(ref hand: Hand, cap_id: u64) {
    let mut roster = array![];
    for id in hand.roster.span() {
        if *id != cap_id {
            roster.append(*id);
        }
    }
    roster.append(cap_id);
    hand.roster = roster;
}
