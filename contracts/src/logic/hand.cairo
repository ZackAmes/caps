use caps::models::game::Hand;

/// Hand semantics (public + deterministic, no randomness):
/// - hand_size pieces visible at once (4 by default)
/// - the cursor points at the oldest hand position
/// - playing a piece advances the cursor, wrapping around the roster
/// - the window is positional: the 4 roster slots after the cursor
/// - a piece already on the board or dead still occupies its window slot
///   (it just can't be deployed again); the window does not refill —
///   you wait for the cycle to come back around
///
/// The hand is PUBLIC: both players see both hands. No randomness.

pub const HAND_SIZE: u8 = 4;

/// Is this cap in the hand window right now? (Positional check — the
/// caller separately verifies the cap is on bench before allowing Play.)
pub fn is_in_hand(hand: @Hand, cap_id: u64) -> bool {
    let len: u8 = hand.roster.len().try_into().unwrap_or(0);
    if len == 0 {
        return false;
    }
    let cursor: u8 = *hand.cursor;
    let hand_size: u8 = *hand.hand_size;
    let mut i: usize = 0;
    while i < hand.roster.len() {
        if *hand.roster.at(i) == cap_id {
            let pos: u8 = i.try_into().unwrap();
            // wrapping distance from cursor
            let dist = if pos >= cursor {
                pos - cursor
            } else {
                len - cursor + pos
            };
            return dist < hand_size;
        }
        i += 1;
    };
    false
}

/// Advance the cursor by one roster position (wraps). Called after a
/// successful Play so the next piece cycles in.
pub fn advance_cursor(ref hand: Hand) {
    let len: u8 = hand.roster.len().try_into().unwrap_or(0);
    if len == 0 {
        return;
    }
    let cur: u8 = hand.cursor;
    hand.cursor = (cur + 1) % len;
}

/// The cap ids currently visible in the hand window (positional). Used by
/// the client via get_hand.
pub fn window_ids(hand: @Hand) -> Array<u64> {
    let mut out = ArrayTrait::new();
    let len: u8 = hand.roster.len().try_into().unwrap_or(0);
    let cursor: u8 = *hand.cursor;
    let hand_size: u8 = *hand.hand_size;
    if len == 0 {
        return out;
    }
    let mut k: u8 = 0;
    while k < hand_size {
        let idx: usize = ((cursor + k) % len).into();
        out.append(*hand.roster.at(idx));
        k += 1;
    };
    out
}
