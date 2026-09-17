use caps::logic::track::BoardGeometry;
use caps::logic::ops::{apply_damage, apply_heal, apply_shield};
use caps::logic::passives::bonus;
use caps::logic::track::{is_walkable, within_range};
use caps::models::cap::{Cap, get_position, is_on_board};
use caps::models::effect::{PassiveKind, Relation};
use caps::models::set_data::{CapType, SetOpDamage, SetOpHeal, SetOpShield};
use caps::models::stack::{AbilityStack, ImpactKind, Schedule, Selection, StackEntry};

pub fn schedule(
    ref stack: AbilityStack,
    source_id: u64,
    player_slot: u8,
    turn: u64,
    layout: BoardGeometry,
    request: Schedule,
) {
    assert!(request.delay >= 1 && request.delay <= 8, "Delay must be 1 to 8");
    assert!(stack.entries.len() < 32, "Ability stack is full");
    assert!(request.impact.amount > 0, "Empty delayed impact");
    let (width, height) = caps::logic::track::get_board_dimensions(layout);
    assert!(width > 0 && height > 0, "Unknown layout");
    match request.impact.selection {
        Selection::Row(row) => { assert!(row < height, "Invalid row"); },
        Selection::Column(column) => { assert!(column < width, "Invalid column"); },
        Selection::Within(zone) => {
            assert!(
                is_walkable(layout, zone.center) && zone.radius <= width * height - 1,
                "Invalid zone",
            );
        },
        Selection::Piece(id) => { assert!(id != 0, "Invalid piece target"); },
    }
    stack.next_id += 1;
    stack
        .entries
        .append(
            StackEntry {
                id: stack.next_id,
                source_id,
                player_slot,
                announced_turn: turn,
                ready_turn: turn + request.delay.into() + 1,
                impact: request.impact,
            },
        );
}

pub fn counter(ref stack: AbilityStack, id: u64) {
    let mut entries = array![];
    for entry in stack.entries.span() {
        if *entry.id != id {
            entries.append(*entry);
        }
    }
    stack.entries = entries;
}

/// Strict LIFO: a not-yet-ready top blocks older entries even if they are ready.
pub fn pop_ready(ref stack: AbilityStack, boundary: u64) -> Option<StackEntry> {
    if stack.entries.is_empty() {
        return Option::None;
    }
    let top = *stack.entries.at(stack.entries.len() - 1);
    if top.ready_turn > boundary {
        return Option::None;
    }
    counter(ref stack, top.id);
    Option::Some(top)
}

fn selected(entry: StackEntry, cap: Cap, layout: BoardGeometry) -> bool {
    if !is_on_board(@cap) {
        return false;
    }
    let friendly = cap.player_slot == entry.player_slot;
    match entry.impact.relation {
        Relation::Ally => { if !friendly {
            return false;
        } },
        Relation::Enemy => { if friendly {
            return false;
        } },
        Relation::Any => {},
    }
    let pos = get_position(@cap).unwrap();
    match entry.impact.selection {
        Selection::Piece(id) => cap.id == id,
        Selection::Row(row) => pos.y == row,
        Selection::Column(column) => pos.x == column,
        Selection::Within(zone) => within_range(layout, zone.center, pos, zone.radius.into()),
    }
}

/// One area impact is simultaneous: mitigation and target selection use one snapshot.
/// Completed announcements survive source death/capture; missing targets simply do nothing.
pub fn resolve(entry: StackEntry, ref caps: Array<Cap>, definitions: @Array<CapType>, layout: BoardGeometry) {
    let snapshot = caps.clone();
    for cap in snapshot.span() {
        if selected(entry, *cap, layout) {
            match entry.impact.kind {
                ImpactKind::Damage => {
                    let reduction = bonus(
                        PassiveKind::DamageReduction, *cap, @snapshot, definitions, layout,
                    );
                    let amount = if entry.impact.amount > reduction {
                        entry.impact.amount - reduction
                    } else {
                        0
                    };
                    apply_damage(ref caps, SetOpDamage { target_cap: *cap.id, amount });
                },
                ImpactKind::Heal => {
                    for def in definitions.span() {
                        if *def.id == *cap.cap_type {
                            apply_heal(
                                ref caps,
                                SetOpHeal {
                                    target_cap: *cap.id,
                                    amount: entry.impact.amount,
                                    max_health: *def.max_health,
                                },
                            );
                        }
                    }
                },
                ImpactKind::Shield => {
                    apply_shield(
                        ref caps, SetOpShield { target_cap: *cap.id, amount: entry.impact.amount },
                    );
                },
            }
        }
    }
}
