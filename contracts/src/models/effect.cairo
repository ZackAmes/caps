use caps::models::game::Vec2;

/// Persistent state change attached to a cap or a tile.
/// Created by set-contract abilities (via SetOp::ApplyEffect), stored and
/// ticked by the core. Sets never touch stored effects directly.
#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Debug, Introspect)]
#[dojo::model]
pub struct Effect {
    #[key]
    pub game_id: u64,
    #[key]
    pub effect_id: u64,
    pub effect_type: EffectType,
    pub target: EffectTarget,
    pub remaining_triggers: u8,
}

/// The complete effect vocabulary. Values are per-trigger magnitudes.
#[derive(Copy, Drop, Serde, PartialEq, Default, DojoStore, Debug, Introspect)]
pub enum EffectType {
    #[default]
    None,
    // ── combat modifiers ──
    /// Next attack deals +N damage.
    DamageBuff: u8,
    /// Absorbs N damage before health. Decays when hit.
    Shield: u8,
    /// Heals N at end of turn.
    Heal: u8,
    /// Deals N damage at end of turn (burn/poison).
    DOT: u8,
    // ── movement / action modifiers ──
    /// +N move steps for this turn's Move actions.
    MoveBonus: u8,
    /// Attacks deal +N damage.
    AttackBonus: u8,
    /// Extend ability range by N (chebyshev).
    BonusRange: u8,
    /// Move costs N less energy.
    MoveDiscount: u8,
    /// Abilities cost N less energy.
    AbilityDiscount: u8,
    // ── economy / control ──
    /// +N energy at start of turn.
    ExtraEnergy: u8,
    /// Target is stunned: skips its next turn.
    Stun: u8,
    /// Repeat the target's next ability N times.
    Double: u8,
    /// Attack costs N less energy (free attacks).
    AttackDiscount: u8,
}

/// What an effect is attached to.
#[derive(Copy, Drop, Serde, PartialEq, Default, DojoStore, Debug, Introspect)]
pub enum EffectTarget {
    #[default]
    None,
    /// Attached to a cap.
    Cap: u64,
    /// Attached to a tile — a zone. Caps standing in it re-acquire the
    /// effect each turn (implemented by the core's tick loop).
    Square: Vec2,
}

/// When in the turn an effect applies. Derived from the effect type so
/// set contracts can't choose arbitrary timings.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Introspect)]
pub enum Timing {
    /// Applied before the turn player acts (energy grants, stuns).
    StartOfTurn,
    /// Applied during each action of the turn (cost discounts, bonuses).
    MoveStep,
    /// Applied after all actions resolve (DOT, heals).
    EndOfTurn,
}

#[generate_trait]
pub impl EffectImpl of EffectTrait {
    fn new(
        game_id: u64,
        effect_id: u64,
        effect_type: EffectType,
        target: EffectTarget,
        remaining_triggers: u8,
    ) -> Effect {
        Effect { game_id, effect_id, effect_type, target, remaining_triggers }
    }

    /// Decrement remaining triggers; returns true if the effect is still
    /// alive after this tick.
    fn trigger(ref self: Effect) -> bool {
        if self.remaining_triggers > 0 {
            self.remaining_triggers -= 1;
        }
        self.remaining_triggers > 0
    }

    fn get_timing(self: @Effect) -> Timing {
        match self.effect_type {
            EffectType::None => Timing::StartOfTurn,
            EffectType::ExtraEnergy(_) => Timing::StartOfTurn,
            EffectType::Stun(_) => Timing::StartOfTurn,
            EffectType::Heal(_) => Timing::EndOfTurn,
            EffectType::DOT(_) => Timing::EndOfTurn,
            // everything else resolves during actions
            _ => Timing::MoveStep,
        }
    }
}

// ── Passives ──
// Passive abilities are always-on piece traits declared by the set
// contract in CapType. The core evaluates them at defined trigger
// points — sets cannot run arbitrary code.

/// A passive ability declared on a CapType.
#[derive(Copy, Drop, Serde, Debug, Introspect)]
pub struct Passive {
    pub passive_type: PassiveType,
}

/// Cairo enums only support tuple payloads — each passive type gets its
/// own single-field struct (same pattern as SetOp).
#[derive(Copy, Drop, Serde, PartialEq, Default, Debug, Introspect)]
pub enum PassiveType {
    #[default]
    None,
    Aura: SetPassiveAura,
    DamageReduction: SetPassiveDamageReduction,
    ConditionalAttack: SetPassiveConditionalAttack,
    Regeneration: SetPassiveRegeneration,
    FreeFirstAttack,
}

#[derive(Copy, Drop, Serde, PartialEq, Debug, Introspect)]
pub struct SetPassiveAura {
    pub effect: EffectType,
    pub radius: u8,
}
#[derive(Copy, Drop, Serde, PartialEq, Debug, Introspect)]
pub struct SetPassiveDamageReduction {
    pub amount: u16,
}
#[derive(Copy, Drop, Serde, PartialEq, Debug, Introspect)]
pub struct SetPassiveConditionalAttack {
    pub amount: u16,
    pub condition: Condition,
}
#[derive(Copy, Drop, Serde, PartialEq, Debug, Introspect)]
pub struct SetPassiveRegeneration {
    pub amount: u16,
}

/// Conditions the core can evaluate. Tuple payloads (Cairo enum style).
#[derive(Copy, Drop, Serde, PartialEq, Default, Debug, Introspect)]
pub enum Condition {
    #[default]
    None,
    MinAlliesOnBoard: u8,
    HasAdjacentAlly,
    EnemyInRange: u8,
    HealthBelow: u8,
    OnEnemyHalf,
}
