use caps::logic::track::BoardGeometry;
use caps::logic::track::within_range;
use caps::models::cap::{Cap, get_position, is_on_board};
use caps::models::effect::{Condition, Passive, PassiveKind, PassiveTarget, Relation};
use caps::models::set_data::CapType;
use core::num::traits::SaturatingAdd;

fn related(source: Cap, other: Cap, relation: Relation) -> bool {
    source.id != other.id
        && is_on_board(@other)
        && match relation {
            Relation::Ally => source.player_slot == other.player_slot,
            Relation::Enemy => source.player_slot != other.player_slot,
            Relation::Any => true,
        }
}

pub fn condition_met(
    condition: Condition, source: Cap, max_health: u16, caps: @Array<Cap>, layout: BoardGeometry,
) -> bool {
    let pos = match get_position(@source) {
        Option::Some(p) => p,
        _ => { return false; },
    };
    let (_, height) = caps::logic::track::get_board_dimensions(layout);
    match condition {
        Condition::HealthBelowPercent(percent) => {
            let hp: u32 = source.health.into();
            let max: u32 = max_health.into();
            hp * 100 < max * percent.into()
        },
        Condition::OnEnemyHalf => if source.player_slot == 0 {
            pos.y > (height - 1) / 2
        } else {
            pos.y < height / 2
        },
        Condition::AlliesOnBoard(minimum) => {
            let mut count: u16 = 0;
            for c in caps.span() {
                if *c.player_slot == source.player_slot && is_on_board(c) {
                    count += 1;
                }
            }
            count >= minimum.into()
        },
        _ => {
            for c in caps.span() {
                let other = *c;
                if let Option::Some(p) = get_position(c) {
                    let found = match condition {
                        Condition::AllyWithin(radius) => related(source, other, Relation::Ally)
                            && within_range(layout, pos, p, radius.into()),
                        Condition::EnemyWithin(radius) => related(source, other, Relation::Enemy)
                            && within_range(layout, pos, p, radius.into()),
                        Condition::PieceInRow(relation) => related(source, other, relation)
                            && pos.y == p.y,
                        Condition::PieceInColumn(relation) => related(source, other, relation)
                            && pos.x == p.x,
                        _ => false,
                    };
                    if found {
                        return true;
                    }
                }
            }
            false
        },
    }
}

pub fn is_active(
    passive: Passive, source: Cap, max_health: u16, caps: @Array<Cap>, layout: BoardGeometry,
) -> bool {
    if !is_on_board(@source) {
        return false;
    }
    for condition in passive.conditions {
        if !condition_met(*condition, source, max_health, caps, layout) {
            return false;
        }
    }
    true
}

fn affects(passive: Passive, source: Cap, target: Cap, layout: BoardGeometry) -> bool {
    if !is_on_board(@target) {
        return false;
    }
    match passive.target {
        PassiveTarget::SelfCap => source.id == target.id,
        _ => {
            let (relation, radius) = match passive.target {
                PassiveTarget::AlliesWithin(n) => (Relation::Ally, n),
                PassiveTarget::EnemiesWithin(n) => (Relation::Enemy, n),
                PassiveTarget::AllWithin(n) => (Relation::Any, n),
                _ => (Relation::Any, 0),
            };
            related(source, target, relation)
                && within_range(
                    layout,
                    get_position(@source).unwrap(),
                    get_position(@target).unwrap(),
                    radius.into(),
                )
        },
    }
}

/// Each eligible source contributes once. Stacking is additive and saturates at u16::MAX.
/// Conditions read base board state only: passive bonuses cannot recursively enable passives.
pub fn bonus(
    kind: PassiveKind, target: Cap, caps: @Array<Cap>, definitions: @Array<CapType>, layout: BoardGeometry,
) -> u16 {
    let mut result: u16 = 0;
    for source in caps.span() {
        if is_on_board(source) {
            for def in definitions.span() {
                if *def.id == *source.cap_type {
                    for passive in def.passives.span() {
                        if *passive.kind == kind
                            && is_active(*passive, *source, *def.max_health, caps, layout)
                            && affects(*passive, *source, target, layout) {
                            result = result.saturating_add(*passive.amount);
                        }
                    }
                }
            }
        }
    }
    result
}
