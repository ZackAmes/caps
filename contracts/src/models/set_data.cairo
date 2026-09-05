use caps::models::cap::{Cap, Location};
use caps::models::effect::{
    Condition, Effect, EffectTarget, EffectTrait, EffectType, Passive, PassiveType, Timing,
};
use caps::models::game::Vec2;

/// Piece definition. OWNED BY THE SET CONTRACT — this struct is only a
/// data exchange format between the set contract and the core. Stats are
/// read by the core to enforce costs/ranges; ability execution is
/// delegated to the set via ISetInterface.
#[derive(Drop, Serde, Debug, Clone, Introspect)]
pub struct CapType {
    pub id: u16,
    pub name: ByteArray,
    pub description: ByteArray,
    // ── core-consumed stats ──
    pub max_health: u16,
    pub attack: u16,
    /// Steps per Move action along the layout (1 = standard).
    pub move_range: u8,
    /// Chebyshev range for contact combat (future: ranged contact).
    pub attack_range: u8,
    /// Reserved set metadata. Deployment uses a normal action, never energy.
    pub play_cost: u8,
    /// Reserved set metadata. Movement uses an action/bonus move, never energy.
    pub move_cost: u8,
    /// Energy to activate the ability.
    pub ability_cost: u8,
    // ── ability metadata (display + targeting) ──
    pub ability_description: ByteArray,
    pub ability_target: TargetType,
    /// Relative offsets (from the piece) the ability can target.
    pub ability_range: Array<Vec2>,
    /// Always-on passive (None = no passive).
    pub passive: Passive,
}

/// Declarative ability targeting. The core validates targeting legality
/// (range + ownership + occupancy) so every set gets identical rules for
/// free and sets cannot cheat targeting.
#[derive(Copy, Drop, Serde, PartialEq, Default, DojoStore, Debug, Introspect)]
pub enum TargetType {
    #[default]
    /// Passive piece — no active ability.
    None,
    /// Targets the acting piece itself.
    SelfCap,
    /// A friendly cap within ability_range.
    TeamCap,
    /// An enemy cap within ability_range.
    OpponentCap,
    /// Any cap (friend or foe) within ability_range.
    AnyCap,
    /// Any tile within ability_range, even empty.
    AnySquare,
}

/// The acting piece + a snapshot of everything an ability may read.
/// Passed to `ISetInterface::activate_ability`. Immutable from the set's
/// perspective — sets return SetOps instead of mutating anything.
#[derive(Drop, Serde, Debug, Clone)]
pub struct AbilityContext {
    pub game_id: u64,
    pub layout: u8,
    pub turn_count: u64,
    /// Energy the turn player has remaining (after prior actions).
    pub energy: u8,
    /// The piece activating the ability.
    pub actor: ActorInfo,
    /// All live caps (board + bench).
    pub caps: Span<CapInfo>,
    /// All live effects in this game.
    pub effects: Span<EffectSnapshot>,
}

/// The acting piece, flattened for set consumption.
#[derive(Copy, Drop, Serde, Debug)]
pub struct ActorInfo {
    pub id: u64,
    pub owner: felt252,
    pub player_slot: u8,
    pub cap_type: u16,
    pub x: u8,
    pub y: u8,
    pub health: u16,
}

/// Cap snapshot for set consumption (no Dojo model, no storage semantics).
#[derive(Copy, Drop, Serde, Debug)]
pub struct CapInfo {
    pub id: u64,
    pub owner: felt252,
    pub player_slot: u8,
    pub cap_type: u16,
    pub x: u8,
    pub y: u8,
    /// 0 if on bench (x/y null on the Cap model).
    pub health: u16,
}

/// Effect snapshot for set consumption.
#[derive(Copy, Drop, Serde, Debug)]
pub struct EffectSnapshot {
    pub effect_type: EffectType,
    pub target_cap_id: u64,
    pub remaining_triggers: u8,
}

// ─────────────────────────────────────────────────────────────────
// SetOps — the complete vocabulary of state mutations an ability
// can request. The core validates and applies them sequentially.
// See docs/SET_OPS.md for the design rationale.
// ─────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, Serde, Debug)]
pub enum SetOp {
    Damage: SetOpDamage,
    Heal: SetOpHeal,
    Shield: SetOpShield,
    Sacrifice: SetOpSacrifice,
    Push: SetOpPush,
    Teleport: SetOpTeleport,
    Swap: SetOpSwap,
    ApplyEffect: SetOpApplyEffect,
    Cleanse: SetOpCleanse,
    CleansePositive: SetOpCleansePositive,
    Summon: SetOpSummon,
    /// Turn-local allowances, granted to the activating player.
    ExtraMoves: u8,
    ExtraActions: u8,
}

// One struct per op. Verbosity is the price of Cairo's enum limitations —
// and it reads fine: SetOp::Damage(SetOpDamage { target_cap: 5, amount: 4 }).
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpDamage {
    pub target_cap: u64,
    pub amount: u16,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpHeal {
    pub target_cap: u64,
    pub amount: u16,
    /// Max health of the target (set passes it so the core can clamp).
    pub max_health: u16,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpShield {
    pub target_cap: u64,
    pub amount: u16,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpSacrifice {
    pub target_cap: u64,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpApplyEffect {
    pub target_cap: u64,
    pub effect: EffectType,
    pub triggers: u8,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpPush {
    pub target_cap: u64,
    /// 0=+x, 1=-x, 2=+y, 3=-y
    pub direction: u8,
    pub steps: u8,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpTeleport {
    pub target_cap: u64,
    pub to: Vec2,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpSwap {
    pub cap_a: u64,
    pub cap_b: u64,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpCleanse {
    pub target_cap: u64,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpCleansePositive {
    pub target_cap: u64,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetOpSummon {
    pub cap_type_id: u16,
    pub at: Vec2,
}

/// Client-facing flavor/animations. Ops are state truth; events are
/// presentation. Clients fall back to animating ops if no events emitted.
#[derive(Copy, Drop, Serde, Debug)]
pub enum SetEvent {
    Flavor: SetEventFlavor,
    DamageDealt: SetEventDamageDealt,
    EffectGained: SetEventEffectGained,
    PieceMoved: SetEventPieceMoved,
    Summoned: SetEventSummoned,
}

#[derive(Copy, Drop, Serde, Debug)]
pub struct SetEventFlavor {
    pub code: u8,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetEventDamageDealt {
    pub source: u64,
    pub target: u64,
    pub amount: u16,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetEventEffectGained {
    pub cap_id: u64,
    pub effect: EffectType,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetEventPieceMoved {
    pub cap_id: u64,
    pub from: Vec2,
    pub to: Vec2,
}
#[derive(Copy, Drop, Serde, Debug)]
pub struct SetEventSummoned {
    pub cap_id: u64,
    pub cap_type: u16,
    pub at: Vec2,
}

/// What `activate_ability` returns: ops to apply + events to animate.
#[derive(Drop, Serde, Debug)]
pub struct SetOutput {
    pub ops: Span<SetOp>,
    pub events: Span<SetEvent>,
}


// ── Effect ticking + passive evaluation (logic lives with the types) ──

/// Result of ticking effects: the surviving effects plus any scalar
/// outputs the caller needs.
#[derive(Drop)]
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

#[derive(Copy, Drop, Serde, Debug)]
pub struct DotHit {
    pub cap_id: u64,
    pub amount: u16,
}

#[derive(Copy, Drop, Serde, Debug)]
pub struct HealHit {
    pub cap_id: u64,
    pub amount: u16,
}

#[generate_trait]
pub impl EffectTicker of EffectTickerTrait {
    /// Tick all effects with the given timing. Returns surviving effects
    /// (with remaining_triggers decremented) plus per-effect outputs.
    /// NOTE: DOT/Heal damage application is done by the CALLER (needs
    /// cap_type lookup for max_health clamping) — we just report amounts.
    fn tick_effects(effects: @Array<Effect>, timing: Timing, turn_count: u64) -> TickResult {
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
                                result.dot_damage.append(DotHit { cap_id, amount: dmg.into() });
                            }
                        },
                        EffectType::Heal(heal) => {
                            if let EffectTarget::Cap(cap_id) = e.target {
                                result.heal_amounts.append(HealHit { cap_id, amount: heal.into() });
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
        }
        result
    }
}

/// Evaluate a condition against the board state.
/// `cap` is the piece the condition belongs to, `caps` is all live caps.
fn _get_loc(cap: Cap) -> Option<Vec2> {
    match cap.location {
        Location::Board(p) => Option::Some(p),
        _ => Option::None,
    }
}

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
                    if c.id != cap.id
                        && c.player_slot == cap.player_slot
                        && caps::models::cap::is_on_board(@c) {
                        count += 1;
                    }
                    i += 1;
                }
                // +1 to include self
                count + 1 >= min
            },
            Condition::HasAdjacentAlly => {
                let pos = match cap.location {
                    Location::Board(p) => p,
                    _ => { return false; },
                };
                let mut found = false;
                for c in caps.span() {
                    if *c.id != cap.id && *c.player_slot == cap.player_slot {
                        if let Location::Board(v) = c.location {
                            if caps::models::cap::dist(pos, *v) <= 1 {
                                found = true;
                            }
                        }
                    }
                }
                found
            },
            Condition::EnemyInRange(radius) => {
                let pos = match cap.location {
                    Location::Board(p) => p,
                    _ => { return false; },
                };
                let mut i: usize = 0;
                let mut found = false;
                while i < caps.len() && !found {
                    let c = *caps.at(i);
                    if c.player_slot != cap.player_slot {
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
                            let d = if dx > dy {
                                dx
                            } else {
                                dy
                            };
                            if d <= radius.into() {
                                found = true;
                            }
                        }
                    }
                    i += 1;
                }
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
                    _ => { return false; },
                };
                if cap.player_slot == 0 {
                    pos.y >= 3
                } else {
                    pos.y <= 1
                }
            },
        }
    }
}

/// Evaluate a passive: does it modify incoming damage?
/// Returns reduced damage (min 0).
pub fn apply_damage_reduction(passive: Passive, damage: u16) -> u16 {
    match passive.passive_type {
        PassiveType::DamageReduction(dr) => {
            let amount = dr.amount;
            if damage > amount {
                damage - amount
            } else {
                0
            }
        },
        _ => damage,
    }
}

/// Does a conditional attack bonus apply right now?
/// Returns the bonus amount (0 if condition unmet).
pub fn conditional_attack_bonus(passive: Passive, cap: Cap, caps: @Array<Cap>) -> u16 {
    match passive.passive_type {
        PassiveType::ConditionalAttack(ca) => {
            let amount = ca.amount;
            let condition = ca.condition;
            if ConditionEvaluatorTrait::is_met(condition, cap, caps) {
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
    fn aura_ops(source: Cap, passive: Passive, caps: @Array<Cap>) -> Array<SetOp> {
        let mut ops = ArrayTrait::new();
        if let PassiveType::Aura(aura_data) = passive.passive_type {
            let effect = aura_data.effect;
            let radius = aura_data.radius;
            let pos = match source.location {
                Location::Board(p) => p,
                _ => { return ops; },
            };
            let mut i: usize = 0;
            while i < caps.len() {
                let c = *caps.at(i);
                if c.id != source.id
                    && c.player_slot == source.player_slot
                    && caps::models::cap::is_on_board(@c) {
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
                        let d = if dx > dy {
                            dx
                        } else {
                            dy
                        };
                        if d <= radius.into() {
                            ops
                                .append(
                                    SetOp::ApplyEffect(
                                        SetOpApplyEffect { target_cap: c.id, effect, triggers: 1 },
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
