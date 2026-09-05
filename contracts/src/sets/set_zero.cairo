use caps::models::effect::{Passive, PassiveType};
use caps::models::game::Vec2;
use caps::models::set_data::{
    AbilityContext, CapInfo, CapType, SetOp, SetOpDamage, SetOpHeal, SetOpShield, SetOutput,
    TargetType,
};

/// SET ZERO — the reference piece set. 6 pieces: a generator + 5
/// units exercising different ability patterns. Stats and abilities are
/// defined entirely here; the core reads them via ISetInterface.

pub fn cap_type_of(id: u16) -> Option<CapType> {
    if id == 0 {
        // Generator — a vulnerable mobile energy source.
        Option::Some(
            CapType {
                id: 0,
                name: "Generator",
                description: "Generates 1 energy each owner turn while on the board.",
                max_health: 5,
                attack: 1,
                move_range: 1,
                attack_range: 1,
                play_cost: 0,
                move_cost: 0,
                ability_cost: 0,
                ability_description: "None",
                ability_target: TargetType::None,
                ability_range: array![],
                passive: Passive { passive_type: PassiveType::EnergyGeneration(1) },
            },
        )
    } else if id == 1 {
        // Striker — cheap aggressive unit. "Deal 2 damage to an enemy."
        Option::Some(
            CapType {
                id: 1,
                name: "Striker",
                description: "Fast, aggressive.",
                max_health: 6,
                attack: 2,
                move_range: 1,
                attack_range: 1,
                play_cost: 0,
                move_cost: 0,
                ability_cost: 2,
                ability_description: "Deal 2 damage to an enemy in range",
                ability_target: TargetType::OpponentCap,
                ability_range: array![
                    Vec2 { x: 1, y: 0 }, Vec2 { x: 0, y: 1 }, Vec2 { x: 1, y: 1 },
                ],
                passive: Passive { passive_type: PassiveType::None },
            },
        )
    } else if id == 2 {
        // Guardian — tanky support. "Shield an ally for 3."
        Option::Some(
            CapType {
                id: 2,
                name: "Guardian",
                description: "Protects the team.",
                max_health: 10,
                attack: 1,
                move_range: 1,
                attack_range: 1,
                play_cost: 0,
                move_cost: 0,
                ability_cost: 2,
                ability_description: "Give an ally 3 shield",
                ability_target: TargetType::TeamCap,
                ability_range: array![
                    Vec2 { x: 1, y: 0 }, Vec2 { x: 0, y: 1 }, Vec2 { x: 1, y: 1 },
                ],
                passive: Passive { passive_type: PassiveType::None },
            },
        )
    } else if id == 3 {
        // Medic — sustain. "Heal an ally 3."
        Option::Some(
            CapType {
                id: 3,
                name: "Medic",
                description: "Keeps the team alive.",
                max_health: 7,
                attack: 1,
                move_range: 1,
                attack_range: 1,
                play_cost: 0,
                move_cost: 0,
                ability_cost: 2,
                ability_description: "Heal an ally 3",
                ability_target: TargetType::TeamCap,
                ability_range: array![
                    Vec2 { x: 1, y: 0 }, Vec2 { x: 0, y: 1 }, Vec2 { x: 1, y: 1 },
                ],
                passive: Passive { passive_type: PassiveType::None },
            },
        )
    } else if id == 4 {
        // Blaster — ranged burst. "Deal 4 damage to an enemy at range 3."
        Option::Some(
            CapType {
                id: 4,
                name: "Blaster",
                description: "Long range burst.",
                max_health: 5,
                attack: 1,
                move_range: 1,
                attack_range: 1,
                play_cost: 0,
                move_cost: 0,
                ability_cost: 3,
                ability_description: "Deal 4 damage to an enemy within 3",
                ability_target: TargetType::OpponentCap,
                ability_range: array![
                    Vec2 { x: 1, y: 0 }, Vec2 { x: 2, y: 0 }, Vec2 { x: 3, y: 0 },
                    Vec2 { x: 0, y: 1 }, Vec2 { x: 0, y: 2 }, Vec2 { x: 1, y: 1 },
                    Vec2 { x: 2, y: 2 }, Vec2 { x: 3, y: 3 },
                ],
                passive: Passive { passive_type: PassiveType::None },
            },
        )
    } else if id == 5 {
        // Runner — buys an extra move without using the normal action.
        Option::Some(
            CapType {
                id: 5,
                name: "Runner",
                description: "Spends energy to gain one extra move this turn.",
                max_health: 6,
                attack: 2,
                move_range: 1,
                attack_range: 1,
                play_cost: 0,
                move_cost: 0,
                ability_cost: 2,
                ability_description: "Gain 1 extra move this turn",
                ability_target: TargetType::SelfCap,
                ability_range: array![],
                passive: Passive { passive_type: PassiveType::None },
            },
        )
    } else {
        Option::None
    }
}

/// Execute an ability via the SetOp vocabulary. The core validated the
/// target already; we just emit ops. Pure function — no world access.
pub fn use_ability(ctx: AbilityContext, target: Vec2) -> SetOutput {
    let mut ops: Array<SetOp> = ArrayTrait::new();
    let caps_snapshot = ctx.caps;
    let actor_type: u16 = ctx.actor.cap_type;

    if actor_type == 1 {
        // Striker: deal 2 damage to the enemy at `target`.
        let target_cap = cap_at(caps_snapshot, target);
        if target_cap.is_some() {
            ops.append(SetOp::Damage(SetOpDamage { target_cap: target_cap.unwrap(), amount: 2 }));
        }
    } else if actor_type == 2 {
        // Guardian: shield the ally at `target` for 3.
        let target_cap = cap_at(caps_snapshot, target);
        if target_cap.is_some() {
            ops.append(SetOp::Shield(SetOpShield { target_cap: target_cap.unwrap(), amount: 3 }));
        }
    } else if actor_type == 3 {
        // Medic: heal the ally at `target` for 3.
        let target_cap = cap_at(caps_snapshot, target);
        if target_cap.is_some() {
            ops
                .append(
                    SetOp::Heal(
                        SetOpHeal {
                            target_cap: target_cap.unwrap(),
                            amount: 3,
                            max_health: 20 // generous clamp; heal caps at target's real max via op
                        },
                    ),
                );
        }
    } else if actor_type == 4 {
        // Blaster: deal 4 damage to the enemy at `target`.
        let target_cap = cap_at(caps_snapshot, target);
        if target_cap.is_some() {
            ops.append(SetOp::Damage(SetOpDamage { target_cap: target_cap.unwrap(), amount: 4 }));
        }
    } else if actor_type == 5 {
        ops.append(SetOp::ExtraMoves(1));
    }

    SetOutput { ops: ops.span(), events: array![].span() }
}

fn cap_at(caps: Span<CapInfo>, target: Vec2) -> Option<u64> {
    let mut i: usize = 0;
    while i < caps.len() {
        let c: CapInfo = *caps.at(i);
        if c.x == target.x && c.y == target.y {
            return Option::Some(c.id);
        }
        i += 1;
    }
    Option::None
}


/// The ISetInterface contract for Set Zero. Deployable standalone.
#[dojo::contract]
pub mod set_zero {
    use caps::models::game::Vec2;
    use caps::models::set::ISetInterface;
    use caps::models::set_data::{AbilityContext, CapType, SetOutput};
    use super::{cap_type_of, use_ability};

    #[abi(embed_v0)]
    impl SetZeroImpl of ISetInterface<ContractState> {
        fn get_cap_type(self: @ContractState, id: u16) -> Option<CapType> {
            cap_type_of(id)
        }

        fn activate_ability(self: @ContractState, ctx: AbilityContext, target: Vec2) -> SetOutput {
            use_ability(ctx, target)
        }
    }
}
