use caps::models::game::Vec2;
use caps::models::effect::{Effect, EffectType};

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
    /// Energy to deploy from bench.
    pub play_cost: u8,
    /// Energy per Move action.
    pub move_cost: u8,
    /// Energy to activate the ability.
    pub ability_cost: u8,

    // ── ability metadata (display + targeting) ──
    pub ability_description: ByteArray,
    pub ability_target: TargetType,
    /// Relative offsets (from the piece) the ability can target.
    pub ability_range: Array<Vec2>,
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
