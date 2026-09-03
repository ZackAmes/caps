use caps::models::game::Vec2;
use caps::models::cap::{Cap, Location};
use caps::models::effect::{Effect, EffectTrait, EffectType, EffectTarget};
use caps::models::set_data::{
    SetOp, SetOpDamage, SetOpHeal, SetOpShield, SetOpSacrifice, SetOpPush,
    SetOpTeleport, SetOpSwap, SetOpApplyEffect, SetOpCleanse,
    SetOpCleansePositive,
};
use caps::logic::track::is_walkable;
use core::num::traits::SaturatingAdd;

fn find_idx(caps: @Array<Cap>, cap_id: u64) -> Option<usize> {
    let mut i: usize = 0;
    while i < caps.len() {
        if (*caps.at(i)).id == cap_id {
            return Option::Some(i);
        }
        i += 1;
    };
    Option::None
}

fn occupied(caps: @Array<Cap>, pos: Vec2) -> bool {
    let mut i: usize = 0;
    while i < caps.len() {
        if let Location::Board(v) = (*caps.at(i)).location {
            if v.x == pos.x && v.y == pos.y {
                return true;
            }
        }
        i += 1;
    };
    false
}

fn get_loc(cap: Cap) -> Option<Vec2> {
    match cap.location {
        Location::Board(p) => Option::Some(p),
        _ => Option::None,
    }
}

fn step_dir(pos: Vec2, direction: u8) -> Vec2 {
    let mut x = pos.x;
    let mut y = pos.y;
    if direction == 0 && x < 255 {
        x += 1;
    }
    if direction == 1 && x > 0 {
        x -= 1;
    }
    if direction == 2 && y < 255 {
        y += 1;
    }
    if direction == 3 && y > 0 {
        y -= 1;
    }
    Vec2 { x, y }
}

fn replace_at(ref caps: Array<Cap>, idx: usize, cap: Cap) {
    let mut new_caps: Array<Cap> = ArrayTrait::new();
    let mut k: usize = 0;
    while k < caps.len() {
        if k == idx {
            new_caps.append(cap);
        } else {
            new_caps.append(*caps.at(k));
        }
        k += 1;
    };
    caps = new_caps;
}

/// Apply one op. Returns true if applied, false if dropped (illegal or
/// no-op). Ops fail soft — see docs/SET_OPS.md §3.
/// Individual ref params avoid OpState struct ref-passing compile issues
/// (cairo-lang 2.13 salsa cycle panic with struct-of-arrays refs).
pub fn apply_op(
    ref caps: Array<Cap>,
    ref effects: Array<Effect>,
    actor_id: u64,
    actor_owner: felt252,
    layout: u8,
    ref next_effect_id: u64,
    op: SetOp,
) -> bool {
    match op {
        SetOp::Damage(d) => apply_damage(ref caps, d),
        SetOp::Heal(h) => apply_heal(ref caps, h),
        SetOp::Shield(s) => apply_shield(ref caps, s),
        SetOp::Sacrifice(s) => apply_sacrifice(ref caps, s, actor_id, actor_owner),
        SetOp::Push(p) => apply_push(ref caps, p, layout),
        SetOp::Teleport(t) => apply_teleport(ref caps, t, layout),
        SetOp::Swap(s) => apply_swap(ref caps, s),
        SetOp::ApplyEffect(a) => apply_effect(ref caps, ref effects, ref next_effect_id, a),
        SetOp::Cleanse(c) => apply_cleanse(ref caps, ref effects, c),
        SetOp::CleansePositive(c) => apply_cleanse_positive(ref caps, ref effects, c),
        // Summon needs core coordination (minting) — intercepted by actions.
        SetOp::Summon(_) => false,
        // Zones are a v2 feature.
    }
}

pub fn apply_damage(ref caps: Array<Cap>, op: SetOpDamage) -> bool {
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *caps.at(idx);
    if cap.location == Location::Dead || op.amount == 0 {
        return false;
    }
    if cap.shield >= op.amount {
        cap.shield -= op.amount;
    } else {
        let through = op.amount - cap.shield;
        cap.shield = 0;
        if cap.health > through {
            cap.health -= through;
        } else {
            cap.health = 0;
            cap.location = Location::Dead;
        }
    }
    replace_at(ref caps, idx, cap);
    true
}

pub fn apply_heal(ref caps: Array<Cap>, op: SetOpHeal) -> bool {
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *caps.at(idx);
    if cap.location == Location::Dead || op.amount == 0 || cap.health >= op.max_health {
        return false;
    }
    if cap.health + op.amount > op.max_health {
        cap.health = op.max_health;
    } else {
        cap.health += op.amount;
    }
    replace_at(ref caps, idx, cap);
    true
}

pub fn apply_shield(ref caps: Array<Cap>, op: SetOpShield) -> bool {
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *caps.at(idx);
    if cap.location == Location::Dead || op.amount == 0 {
        return false;
    }
    cap.shield = cap.shield.saturating_add(op.amount);
    replace_at(ref caps, idx, cap);
    true
}

pub fn apply_sacrifice(
    ref caps: Array<Cap>, op: SetOpSacrifice, actor_id: u64, actor_owner: felt252,
) -> bool {
    if op.target_cap == actor_id {
        return false;
    }
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *caps.at(idx);
    if cap.location == Location::Dead || cap.owner != actor_owner {
        return false;
    }
    cap.location = Location::Dead;
    cap.health = 0;
    replace_at(ref caps, idx, cap);
    true
}

pub fn apply_push(ref caps: Array<Cap>, op: SetOpPush, layout: u8) -> bool {
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *caps.at(idx);
    let pos = match get_loc(cap) {
        Option::Some(p) => p,
        Option::None => { return false; },
    };
    if op.steps == 0 {
        return false;
    }
    // Scalar-only loop: mutating a Vec2 in a loop then constructing a
    // Location::Board payload from it triggers a cairo-lang 2.13 salsa
    // cycle panic. Scalar locals are safe.
    let mut cur_x: u8 = pos.x;
    let mut cur_y: u8 = pos.y;
    let mut moved: u8 = 0;
    let mut i: u8 = 0;
    while i < op.steps {
        let next = step_dir(Vec2 { x: cur_x, y: cur_y }, op.direction);
        if !is_walkable(layout, next) || occupied(@caps, next) {
            break;
        }
        cur_x = next.x;
        cur_y = next.y;
        moved += 1;
        i += 1;
    };
    if moved == 0 {
        return false;
    }
    cap.location = Location::Board(Vec2 { x: cur_x, y: cur_y });
    replace_at(ref caps, idx, cap);
    true
}

pub fn apply_teleport(ref caps: Array<Cap>, op: SetOpTeleport, layout: u8) -> bool {
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *caps.at(idx);
    if cap.location == Location::Bench || cap.location == Location::Dead {
        return false;
    }
    if !is_walkable(layout, op.to) || occupied(@caps, op.to) {
        return false;
    }
    cap.location = Location::Board(op.to);
    replace_at(ref caps, idx, cap);
    true
}

pub fn apply_swap(ref caps: Array<Cap>, op: SetOpSwap) -> bool {
    if op.cap_a == op.cap_b {
        return false;
    }
    let idx_a = match find_idx(@caps, op.cap_a) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let idx_b = match find_idx(@caps, op.cap_b) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut a: Cap = *caps.at(idx_a);
    let mut b: Cap = *caps.at(idx_b);
    let pa = match get_loc(a) {
        Option::Some(p) => p,
        Option::None => { return false; },
    };
    let pb = match get_loc(b) {
        Option::Some(p) => p,
        Option::None => { return false; },
    };
    a.location = Location::Board(pb);
    b.location = Location::Board(pa);
    replace_at(ref caps, idx_a, a);
    replace_at(ref caps, idx_b, b);
    true
}

pub fn apply_effect(
    ref caps: Array<Cap>, ref effects: Array<Effect>, ref next_effect_id: u64,
    op: SetOpApplyEffect,
) -> bool {
    if op.triggers == 0 {
        return false;
    }
    let idx = match find_idx(@caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    if (*caps.at(idx)).location == Location::Dead {
        return false;
    }
    let effect_id = next_effect_id;
    next_effect_id += 1;
    effects.append(
        EffectTrait::new(1, effect_id, op.effect, EffectTarget::Cap(op.target_cap), op.triggers),
    );
    true
}

pub fn apply_cleanse(ref caps: Array<Cap>, ref effects: Array<Effect>, op: SetOpCleanse) -> bool {
    remove_effects(ref effects, op.target_cap, false)
}

pub fn apply_cleanse_positive(
    ref caps: Array<Cap>, ref effects: Array<Effect>, op: SetOpCleansePositive,
) -> bool {
    remove_effects(ref effects, op.target_cap, true)
}

/// Remove effects from a cap. `positive=true` strips buffs,
/// `positive=false` strips debuffs (DOT, Stun).
fn remove_effects(ref effects: Array<Effect>, target_cap: u64, positive: bool) -> bool {
    let mut removed = false;
    let mut i: usize = 0;
    while i < effects.len() {
        let e = *effects.at(i);
        if let EffectTarget::Cap(cap_id) = e.target {
            if cap_id == target_cap && is_positive(e.effect_type) == positive {
                let mut remaining: Array<Effect> = ArrayTrait::new();
                let mut j: usize = 0;
                while j < effects.len() {
                    if j != i {
                        remaining.append(*effects.at(j));
                    }
                    j += 1;
                };
                effects = remaining;
                removed = true;
                continue;
            }
        }
        i += 1;
    };
    removed
}

fn is_positive(e: EffectType) -> bool {
    match e {
        EffectType::DOT(_) | EffectType::Stun(_) => false,
        EffectType::None => false,
        _ => true,
    }
}
