use caps::models::game::Vec2;
use caps::models::cap::{Cap, Location};
use caps::models::effect::{Effect, EffectType, EffectTarget};
use caps::models::set_data::{
    SetOp, SetOpDamage, SetOpHeal, SetOpShield, SetOpSacrifice,
};
use core::num::traits::SaturatingAdd;

pub struct OpState {
    pub layout: u8,
    pub caps: Array<Cap>,
    pub effects: Array<Effect>,
    pub actor_id: u64,
    pub actor_owner: felt252,
    pub next_effect_id: u64,
}

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

pub fn apply_op(ref state: OpState, op: SetOp) -> bool {
    match op {
        SetOp::Damage(d) => apply_damage(ref state, d),
        SetOp::Heal(h) => apply_heal(ref state, h),
        SetOp::Shield(s) => apply_shield(ref state, s),
        SetOp::Sacrifice(s) => apply_sacrifice(ref state, s),
        _ => false,
    }
}

pub fn apply_damage(ref state: OpState, op: SetOpDamage) -> bool {
    let idx = match find_idx(@state.caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *state.caps.at(idx);
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
    let mut new_caps: Array<Cap> = ArrayTrait::new();
    let mut k: usize = 0;
    while k < state.caps.len() {
        if k == idx {
            new_caps.append(cap);
        } else {
            new_caps.append(*state.caps.at(k));
        }
        k += 1;
    };
    state.caps = new_caps;
    true
}

pub fn apply_heal(ref state: OpState, op: SetOpHeal) -> bool {
    let idx = match find_idx(@state.caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *state.caps.at(idx);
    if cap.location == Location::Dead || op.amount == 0 || cap.health >= op.max_health {
        return false;
    }
    if cap.health + op.amount > op.max_health {
        cap.health = op.max_health;
    } else {
        cap.health += op.amount;
    }
    let mut new_caps: Array<Cap> = ArrayTrait::new();
    let mut k: usize = 0;
    while k < state.caps.len() {
        if k == idx {
            new_caps.append(cap);
        } else {
            new_caps.append(*state.caps.at(k));
        }
        k += 1;
    };
    state.caps = new_caps;
    true
}

pub fn apply_shield(ref state: OpState, op: SetOpShield) -> bool {
    let idx = match find_idx(@state.caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *state.caps.at(idx);
    if cap.location == Location::Dead || op.amount == 0 {
        return false;
    }
    cap.shield = cap.shield.saturating_add(op.amount);
    let mut new_caps: Array<Cap> = ArrayTrait::new();
    let mut k: usize = 0;
    while k < state.caps.len() {
        if k == idx {
            new_caps.append(cap);
        } else {
            new_caps.append(*state.caps.at(k));
        }
        k += 1;
    };
    state.caps = new_caps;
    true
}

pub fn apply_sacrifice(ref state: OpState, op: SetOpSacrifice) -> bool {
    let idx = match find_idx(@state.caps, op.target_cap) {
        Option::Some(i) => i,
        Option::None => { return false; },
    };
    let mut cap: Cap = *state.caps.at(idx);
    if cap.location == Location::Dead || cap.owner != state.actor_owner {
        return false;
    }
    if op.target_cap == state.actor_id {
        return false;
    }
    cap.location = Location::Dead;
    cap.health = 0;
    let mut new_caps: Array<Cap> = ArrayTrait::new();
    let mut k: usize = 0;
    while k < state.caps.len() {
        if k == idx {
            new_caps.append(cap);
        } else {
            new_caps.append(*state.caps.at(k));
        }
        k += 1;
    };
    state.caps = new_caps;
    true
}
