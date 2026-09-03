use caps::models::game::Vec2;
use caps::models::cap::{Cap, Location};
use caps::models::effect::{Effect, EffectType, EffectTarget, Timing};
use caps::models::set_data::{Condition, PassiveType};
use caps::logic::track::is_walkable;

/// Effect ticking + passive evaluation. Called by take_turn at the
/// defined trigger points. All state mutation happens via returned
/// arrays (no refs across the contract boundary).

/// Result of ticking effects: the surviving effects plus any scalar
/// outputs the caller needs.
pub struct TickResult {
    pub effects: Array<Effect>,
    pub extra_energy: u8,
    /// Cap ids that are stunned this turn.
    pub stunned: Array<u64>,
    /// (cap_id, damage) pairs applied by DOT effects.
    pub dot_damage: Array<DotHit>,
    /// (cap_id, heal) pairs applied by Heal effects.
    pub heal_amounts: Array<HealHit>,
}

pub struct DotHit {
    pub cap_id: u64,
    pub amount: u16,
}

pub struct HealHit {
    pub cap_id: u16,
    pub amount: u16,
}

#[generate_trait]
pub impl EffectTicker of EffectTickerTrait {
    /// Tick all effects with the given timing. Returns surviving effects
    /// (with remaining_triggers decremented) plus per-effect outputs.
    /// NOTE: DOT/Heal damage application is done by the CALLER (needs
    /// cap_type lookup for max_health clamping) — we just report amounts.
    fn tick_effects(
        effects: @Array<Effect>,
        timing: Timing,
        turn_count: u64,
    ) -> TickResult {
        let mut result = TickResult {
            effects: ArrayTrait::new(),
            extra_energy: 0,
            stunned: ArrayTrait::new(),
            dot_damage: ArrayTrait::new(),
            heal_amounts: ArrayTrait::new(),
        };
        let mut i: usize = 0;
        while i < effects.len() {
            let mut e: Effect = *effects.at(i);
            if e.get_timing() != timing {
                result.effects.append(e);
                i += 1;
                continue;
            }

            match timing {
                Timing::StartOfTurn => {
                    e.trigger(); // decrement first, then check survival
                    if e.remaining_triggers > 0 {
                        result.effects.append(e);
                    }
                    match e.effect_type {
                        EffectType::ExtraEnergy(x) => { result.extra_energy += x; },
                        EffectType::Stun(_) => {
                            if let EffectTarget::Cap(cap_id) = e.target {
                                result.stunned.append(cap_id);
                            }
                        },
                        _ => {},
                    }
                },
                Timing::EndOfTurn => {
                    e.trigger();
                    if e.remaining_triggers > 0 {
                        result.effects.append(e);
                    }
                    match e.effect_type {
                        EffectType::DOT(dmg) => {
                            if let EffectTarget::Cap(cap_id) = e.target {
                                result
                                    .dot_damage
                                    .append(DotHit { cap_id, amount: dmg.into() });
                            }
                        },
                        EffectType::Heal(heal) => {
                            if let EffectTarget::Cap(cap_id) = e.target {
                                result
                                    .heal_amounts
                                    .append(HealHit { cap_id: cap_id.try_into().unwrap_or(0), amount: heal.into() });
                            }
                        },
                        _ => {},
                    }
                },
                Timing::MoveStep => {
                    // MoveStep effects tick once per action — handled by
                    // the caller (actions contract) during action processing.
                    result.effects.append(e);
                },
            }
            i += 1;
        };
        result
    }
}

/// Evaluate a condition against the board state.
/// `cap` is the piece the condition belongs to, `caps` is all live caps.
#[generate_trait]
pub impl ConditionEval of ConditionEvaluatorTrait {
    fn is_met(condition: Condition, cap: Cap, caps: @Array<Cap>) -> bool {
        match condition {
            Condition::None => true,
            Condition::MinAlliesOnBoard(min) => {
                let mut count: u8 = 0;
                let mut i: usize = 0;
                while i < caps.len() {
                    let c = *caps.at(i);
                    if c.id != cap.id && c.owner == cap.owner
                        && c.location != Location::Dead {
                        count += 1;
                    }
                    i += 1;
                };
                // +1 to include self
                count + 1 >= min
            },
            Condition::HasAdjacentAlly => {
                // Flat u8 offsets (no signed arithmetic — cairo-lang 2.13
                // salsa panic with i16 loops + enum destructuring)
                let dxs: Array<u8> = array![1, 0, 255, 255, 1, 255, 1, 0];
                let dys: Array<u8> = array![0, 1, 1, 255, 255, 0, 1, 1];
                let pos = match cap.location {
                    Location::Board(p) => p,
                    _ => return false,
                };
                let mut found = false;
                let mut k: usize = 0;
                while k < 8 {
                    let dx = *dxs.at(k);
                    let dy = *dys.at(k);
                    let nx = if dx == 255 { pos.x - 1 } else { pos.x + dx };
                    let ny = if dy == 255 { pos.y - 1 } else { pos.y + dy };
                    let mut j: usize = 0;
                    while j < caps.len() {
                        let c = *caps.at(j);
                        if c.id != cap.id && c.owner == cap.owner {
                            if let Location::Board(v) = c.location {
                                if v.x == nx && v.y == ny {
                                    found = true;
                                }
                            }
                        }
                        j += 1;
                    };
                    k += 1;
                };
                found
            },
            Condition::EnemyInRange(radius) => {
                let pos = match cap.location {
                    Location::Board(p) => p,
                    _ => return false,
                };
                let mut i: usize = 0;
                let mut found = false;
                while i < caps.len() && !found {
                    let c = *caps.at(i);
                    if c.owner != cap.owner {
                        if let Location::Board(v) = c.location {
                            let dx: u32 = if v.x > pos.x {
                                (v.x - pos.x).into()
                            } else {
                                (pos.x - v.x).into()
                            };
                            let dy: u32 = if v.y > pos.y {
                                (v.y - pos.y).into()
                            } else {
                                (pos.y - v.y).into()
                            };
                            let d = if dx > dy { dx } else { dy };
                            if d <= radius.into() {
                                found = true;
                            }
                        }
                    }
                    i += 1;
                };
                found
            },
            Condition::HealthBelow(pct) => {
                // We don't have max_health on the Cap — the caller passes
                // it via the check. For simplicity: health*100 <= pct*100
                // requires max; use a relative check: caller clamps.
                // v1: treat `pct` as an absolute health threshold.
                cap.health <= pct.into()
            },
            Condition::OnEnemyHalf => {
                let pos = match cap.location {
                    Location::Board(p) => p,
                    _ => return false,
                };
                // On 5x5: P1 (starts bottom y=0) is on enemy half if y >= 3
                // P2 (starts top y=4) is on enemy half if y <= 1.
                // We can't tell which player this is without game context,
                // so v1 uses: y >= 2 (crossed the middle).
                pos.y >= 2
            },
        }
    }
}

/// Evaluate a passive: does it modify incoming damage?
/// Returns reduced damage (min 0).
pub fn apply_damage_reduction(passive: Passive, damage: u16) -> u16 {
    match passive.passive_type {
        PassiveType::DamageReduction { amount } => {
            if damage > amount { damage - amount } else { 0 }
        },
        _ => damage,
    }
}

/// Does a conditional attack bonus apply right now?
/// Returns the bonus amount (0 if condition unmet).
pub fn conditional_attack_bonus(
    passive: Passive, cap: Cap, caps: @Array<Cap>,
) -> u16 {
    match passive.passive_type {
        PassiveType::ConditionalAttack { amount, condition } => {
            if ConditionEvaluator::is_met(condition, cap, caps) {
                amount
            } else {
                0
            }
        },
        _ => 0,
    }
}

/// Apply an aura passive: for each ally within radius, append an
/// ApplyEffect op (the caller feeds it into the op applier).
#[generate_trait]
pub impl AuraGen of AuraTrait {
    fn aura_ops(
        source: Cap, passive: Passive, caps: @Array<Cap>,
    ) -> Array<SetOp> {
        let mut ops = ArrayTrait::new();
        if let PassiveType::Aura { effect, radius } = passive.passive_type {
            let pos = match source.location {
                Location::Board(p) => p,
                _ => return ops,
            };
            let mut i: usize = 0;
            while i < caps.len() {
                let c = *caps.at(i);
                if c.id != source.id && c.owner == source.owner
                    && c.location != Location::Dead {
                    if let Location::Board(v) = c.location {
                        let dx: u32 = if v.x > pos.x {
                            (v.x - pos.x).into()
                        } else {
                            (pos.x - v.x).into()
                        };
                        let dy: u32 = if v.y > pos.y {
                            (v.y - pos.y).into()
                        } else {
                            (pos.y - v.y).into()
                        };
                        let d = if dx > dy { dx } else { dy };
                        if d <= radius.into() {
                            ops.append(
                                SetOp::ApplyEffect(
                                    SetOpApplyEffect {
                                        target_cap: c.id,
                                        effect,
                                        triggers: 1,
                                    },
                                ),
                            );
                        }
                    }
                }
                i += 1;
            };
        }
        ops
    }
}
