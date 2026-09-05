> Historical framework design. For implemented gameplay rules, see [GAME_DESIGN.md](./GAME_DESIGN.md). Tower, manual-capture, movement-cost and old hand references below are superseded. The current core also supports turn-local `ExtraMoves` and `ExtraActions` ops.

# Effects & Abilities Framework

This document describes the architecture for piece-specific abilities and
persistent effects, adapted from the original CAPS design (see git history:
`42db712..bdd0836^` — the pre-simplify version) and reworked for the
current track-based game and the set-contract extensibility model.

## 1. Design Goal

**Piece logic lives outside the core game contract.** The core contract owns
movement, combat, capture, win conditions, and the effect lifecycle. Piece
definitions (stats, abilities) live in **Set contracts** that anyone can
deploy. A game references one set contract, so the same core game can be
played with community-made pieces.

```
┌─────────────────────────┐        ┌──────────────────────────┐
│   caps-actions (core)   │        │  set contract (anyone)   │
│                         │        │                          │
│  take_turn()            │───────▶│  get_cap_type(id)        │
│   ├─ movement rules     │ calls  │    → stats + ability meta│
│   ├─ combat resolution  │        │  activate_ability(...)   │
│   ├─ capture rules      │◀───────│    → custom piece logic  │
│   ├─ effect lifecycle   │ reads  │    (runs in set contract │
│   └─ win conditions     │        │     context, returns     │
│                         │        │     effects to store)    │
└─────────────────────────┘        └──────────────────────────┘
```

The core never knows what an ability *does*. It only knows:
1. Which set contract to ask (`game.set_address`)
2. The shape of the question (`ISetInterface` below)
3. How to store and tick the `Effect`s that come back

## 2. CapType — the piece definition (owned by the set contract)

```cairo
#[derive(Drop, Serde, Debug, Clone, Introspect)]
pub struct CapType {
    pub id: u16,
    pub name: ByteArray,
    pub description: ByteArray,

    // Core-consumed stats (the core reads these to enforce rules)
    pub max_health: u16,
    pub attack: u16,
    pub move_range: u8,        // steps per Move action (1 = standard)
    pub attack_range: u8,      // chebyshev range for move-onto contact bonus (future)
    pub play_cost: u8,         // energy to deploy
    pub move_cost: u8,         // energy per move
    pub ability_cost: u8,      // energy to activate

    // Ability metadata
    pub ability_description: ByteArray,
    pub ability_target: TargetType,
    pub ability_range: Array<Vec2>,   // relative offsets the ability can target
}
```

The core contract reads `CapType` via the set contract to know costs and
ranges. The set contract is the **only** place these numbers are defined.

## 3. TargetType — declarative ability targeting

The core validates targeting *declaratively* so every set contract gets the
same rules for free (from the original implementation, unchanged):

```cairo
#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Introspect)]
pub enum TargetType {
    #[default]
    None,          // passive piece, no ability
    SelfCap,       // targets itself
    TeamCap,       // a friendly cap within ability_range
    OpponentCap,   // an enemy cap within ability_range
    AnyCap,        // any cap within ability_range
    AnySquare,     // any tile within ability_range (even empty)
}
```

The core's `TargetTypeImpl::is_valid()` enforces range + ownership rules.
Set contracts cannot cheat targeting; they only define *what happens* after
a legal target is chosen.

## 4. Effect — persistent state changes (owned by the core)

Abilities rarely finish in one action. Buffs, burns, stuns need to persist
across turns. The core owns the effect lifecycle; sets only create them.

```cairo
#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Introspect)]
pub struct Effect {
    #[key] pub game_id: u64,
    #[key] pub effect_id: u64,
    pub effect_type: EffectType,
    pub target: EffectTarget,
    pub remaining_triggers: u8,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Introspect)]
pub enum EffectType {
    #[default] None,
    // combat modifiers
    DamageBuff: u8,      // next attack +N
    Shield: u8,          // absorb N damage before health
    Heal: u8,            // heal N at end of turn
    DOT: u8,             // damage N at end of turn (burn/poison)
    // movement modifiers
    MoveBonus: u8,       // +N move range this turn
    MoveDiscount: u8,    // move costs N less
    AttackBonus: u8,     // attack +N
    AttackDiscount: u8,  // free attacks (N remaining)
    BonusRange: u8,      // +N ability range
    // economy / control
    AbilityDiscount: u8, // ability costs N less
    ExtraEnergy: u8,     // +N energy at start of turn
    Stun: u8,            // target skips its next turn(s)
    Double: u8,          // repeat next ability N times
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Default, Introspect)]
pub enum EffectTarget {
    #[default] None,
    Cap: u64,            // attached to a cap
    Square: Vec2,        // attached to a tile (zones, auras)
}
```

### Effect lifecycle (core-owned)

Every effect has a **timing**, derived from its type:

| Timing | When applied | Examples |
|---|---|---|
| `StartOfTurn` | Before the turn player acts | `ExtraEnergy`, `Stun` |
| `MoveStep` | During each action of the turn | `MoveBonus`, `AttackBonus`, `AbilityDiscount`, `Double` |
| `EndOfTurn` | After all actions resolve | `DOT`, `Heal` |

Each tick decrements `remaining_triggers`; at zero the effect expires and is
erased from the world. The core runs this loop — sets never touch stored
effects directly.

## 5. Energy & turn structure (restored from the original)

The original game had an energy economy that makes abilities meaningful.
Restoring it alongside the track system:

```
Energy per turn: turn 0: 0, turns 1-2: 2, turns 3-4: 5, then 7
Spend on: deploy (play_cost), move (move_cost), ability (ability_cost)
Move-onto-enemy combat costs the move_cost only (attack is baked in)
Unused energy does NOT carry over
```

Actions per turn remain a batched `Array<Action>`; energy is checked
sequentially as each action resolves.

## 6. ISetInterface — the extensibility boundary

Sets are **pure functions**: they receive a snapshot of relevant state and
return a list of **SetOps** (state-mutation intents) plus client-facing
events. They never receive world access, never receive mutable state, and
cannot do anything outside the op vocabulary.

```cairo
#[starknet::interface]
pub trait ISetInterface<T> {
    /// Piece definitions (stats/ability metadata) owned by the set.
    fn get_cap_type(self: @T, id: u16) -> Option<CapType>;

    /// Execute an ability. Snapshot in, ops out. Pure function.
    fn activate_ability(
        self: @T,
        ctx: AbilityContext,      // game/actor/caps/effects snapshot
        target: Vec2,             // pre-validated by the core
    ) -> SetOutput;               // { ops: Span<SetOp>, events: Span<SetEvent> }
}
```

The complete op vocabulary (Damage, Heal, Shield, Push, Teleport, Swap,
Summon, ApplyEffect, TerrainEffect, …), per-op validation rules, budgets,
and worked examples live in **[SET_OPS.md](./SET_OPS.md)**.

### Why ops instead of returning full mutated state

Returning `Game`/`Array<Cap>` copies (Option A) would give set authors
maximum freedom, but the core would then need to re-validate every field to
prevent state corruption — and that validator *is* an implicit op
vocabulary, just undocumented and discovered by trial and error. Making the
vocabulary explicit (Option B) means:

- **Validation is bounded** — per-op checks (existence, occupancy, clamping)
  instead of whole-state re-verification
- **Sets are auditable** — what a set does is a readable op list, not
  arbitrary Cairo; "what could this set do to my game?" has a exact answer
- **Governance has a lever** — the vocabulary is the constitution; new
  mechanics arrive as proposed ops, ratified by vote
- **Sets are simulatable** — pure `(context, target) → ops` functions can
  run client-side for preview and replay
- **Blast radius is bounded** — a buggy/malicious set cannot corrupt other
  players' games or the world

The cost — novel mechanics wait on a core upgrade — is the point: new state
mutations should require process, not trust. See SET_OPS.md §8 for the full
governance surface.

## 7. Ability execution flow (per turn)

```
take_turn(game_id, actions[])
  └─ for each action:
      ├─ Action::Play(pos)      → core: check energy, deploy spot, occupancy
      ├─ Action::Move(pos)      → core: check energy/range/occupancy;
      │                           enemy on tile → combat (attack dmg)
      ├─ Action::Ability(pos)   → core: check energy + TargetType::is_valid()
      │                           → set.activate_ability(cap, target, game, caps)
      │                           → apply returned game mutations + store effects
      └─ Action::ClaimCapture(pos) → core: verify surrounded → return to bench
  └─ apply MoveStep effects per action (bonuses/discounts/doubles)
  └─ End of turn: tick EndOfTurn effects (DOT, Heal)
  └─ prune dead caps, check win conditions
Next turn: tick StartOfTurn effects (energy grants, stuns)
```

## 8. Set 0 (reference implementation)

Set 0 ships with the core as the balanced baseline (from the original,
24 cap types: 4 towers, 4 basics, 4 elites, 4 mages, 8 mythics). Examples:

- **Basic (Red)** — "Deal 4 damage to an enemy" — OpponentCap target
- **Basic (Blue)** — "Heal 5 damage from an ally" — TeamCap target
- **Basic (Yellow)** — "Shield an ally for 5" — TeamCap target
- **Elite (Red)** — "Next attack +1 dmg per damage taken" — SelfCap, creates `AttackBonus`
- **Mage (Blue)** — "Stun a target enemy" — OpponentCap, creates `Stun`
- **Mythic (Green)** — "Repeat the next ally ability" — creates `Double`

The full 24-type roster + `use_ability()` implementations are recoverable
from git (`git show bdd0836^:contracts/src/sets/set_zero.cairo`).

## 9. Client implications

- The client fetches `CapType`s from the set contract (per game) instead of
  the hardcoded `CAP_STATS` table
- Ability buttons render from `ability_description` + `ability_target` +
  `ability_cost`; targeting UX is driven by `TargetType` + `ability_range`
- Effect icons/badges render from live `Effect` models indexed by game

## 10. Migration checklist

- [ ] Restore `Effect` model + `EffectType`/`EffectTarget`/`Timing` (from git)
- [ ] Restore `CapType` + `TargetType` + `is_valid()` (from git)
- [ ] Add `set_address` to `Game`; `Set` model + `ISetInterface`
- [ ] Restore energy economy in `take_turn`
- [ ] Add `Action::Ability(Vec2)` variant
- [ ] Split set_zero into a standalone contract implementing `ISetInterface`
- [ ] Core dispatches abilities via `ISetInterfaceDispatcher`
- [ ] Re-validate returned state from set contracts (sandbox hardening)
- [ ] Client: fetch cap types per game; ability UI; effect badges
- [ ] Update `deploySpot`/combat paths for energy costs
