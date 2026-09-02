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

```cairo
#[starknet::interface]
pub trait ISetInterface<T> {
    /// Core asks: what are the stats/ability-meta for piece type `id`?
    fn get_cap_type(self: @T, id: u16) -> Option<CapType>;

    /// Core asks (after validating target legality): execute the ability.
    /// Returns the game state mutated by the ability + effects to store.
    fn activate_ability(
        ref self: T,
        cap: Cap,                // the acting piece
        target: Vec2,            // validated target
        game: Game,              // current game state
        caps: Array<Cap>,        // all live caps (read-only view)
    ) -> (Game, Array<Effect>, Array<Cap>);
}
```

`Game.set_address` points at the set contract for that game. The core
dispatches through `ISetInterfaceDispatcher`. **A community set contract
implementing just these two functions is a fully legal piece set.**

### Trust model

The set contract receives `Game` and `Array<Cap>` **by value** and returns
mutated copies. This is the original design's key safety trick: the set
contract cannot touch world storage directly. It can only:

- Modify the returned `Game`/`Cap` copies (which the core re-validates and
  writes)
- Emit new `Effect`s (which the core stores and ticks)

The core should re-validate the returned state (health bounds, legal
positions) before writing. Set contracts are sandboxed computation, not
trusted authority. For full decentralization, set contracts should be
verified/open-source; for friend games, any contract works.

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
