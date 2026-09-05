> Historical framework design. For implemented gameplay rules, see [GAME_DESIGN.md](./GAME_DESIGN.md). Tower, manual-capture, movement-cost and old hand references below are superseded. The current core also supports turn-local `ExtraMoves` and `ExtraActions` ops.

# Set Operations (SetOps) — The Ability Vocabulary

This document defines the **op vocabulary** — the complete set of state
mutations a piece ability can perform. It is the "constitution" of the
set-contract system: set authors compose ops; the core validates and applies
them. Anything not expressible with these ops requires a core upgrade
(a governance decision), never a trust assumption.

Companion to [EFFECTS_FRAMEWORK.md](./EFFECTS_FRAMEWORK.md).

## 1. The Contract Between Core and Sets

```cairo
#[starknet::interface]
pub trait ISetInterface<T> {
    /// Piece definitions (stats + ability metadata) owned by the set.
    fn get_cap_type(self: @T, id: u16) -> Option<CapType>;

    /// Execute an ability. Receives an immutable snapshot of everything
    /// relevant; returns ONLY ops + events. Never receives world access.
    fn activate_ability(
        self: @T,
        ctx: AbilityContext,      // snapshot: actor, board, effects, energy
        target: Vec2,             // pre-validated by the core
    ) -> SetOutput;
}
```

**Snapshot in:**

```cairo
pub struct AbilityContext {
    pub game: Game,              // id, layout, turn_count, energy (read-only)
    pub actor: Cap,              // the piece using the ability
    pub caps: Span<Cap>,         // all live caps on the board + bench
    pub effects: Span<Effect>,   // all live effects in this game
}
```

**Ops out:**

```cairo
pub struct SetOutput {
    pub ops: Span<SetOp>,        // state mutations to apply (see §2)
    pub events: Span<SetEvent>,  // client-facing flavor text/animations
}
```

The set contract is a **pure function**: `(context, target) → ops + events`.
No world handle. No storage writes. Same inputs → same outputs, on any
chain, at any time. That makes sets auditable, simulatable client-side, and
impossible to grief with.

## 2. The Vocabulary

### 2.1 Combat ops

| Op | Fields | Core validation |
|---|---|---|
| `Damage` | `target_cap: u64, amount: u16, source: DamageSource` | target exists & alive; amount > 0 |
| `Heal` | `target_cap: u64, amount: u16` | target alive; heals up to max only |
| `Shield` | `target_cap: u64, amount: u16` | target alive; shield is temporary (decays end of next turn) |
| `SelfDestruct` | — | actor dies (cannot kill towers this way? — design call) |
| `Sacrifice` | `target_cap: u64` (must be actor's own) | dies, bypassing capture (no bench return) |

`DamageSource` distinguishes `Ability` from `Retaliation`/`Trap` so future
rules ("takes 1 less damage from abilities") can discriminate.

### 2.2 Movement ops

| Op | Fields | Core validation |
|---|---|---|
| `Push` | `target_cap: u64, direction: u8, steps: u8` | each step tile walkable + unoccupied; stops early if blocked; cannot push onto/over towers |
| `Teleport` | `target_cap: u64, to: Vec2` | `to` walkable + unoccupied + adjacent-to-something? (design call: constrain or it's degenerate) |
| `Swap` | `cap_a: u64, cap_b: u64` | both alive; both tiles walkable; can swap actor with target |

Push is the workhorse for track play: shoving pieces around the perimeter
creates position pressure without killing. Steps resolve **along the track**
the same way normal movement does.

### 2.3 Effect ops

| Op | Fields | Notes |
|---|---|---|
| `ApplyEffect` | `target_cap: u64, effect: EffectType, triggers: u8` | the full EffectType vocabulary (see framework doc); core enforces stacking rules |
| `Cleanse` | `target_cap: u64` | removes all negative effects (DOT, Stun) |
| `CleansePositive` | `target_cap: u64` | removes buffs — dispel play |

### 2.4 Board ops (the spicy ones)

| Op | Fields | Core validation |
|---|---|---|
| `Summon` | `cap_type_id: u16, at: Vec2` | tile walkable + unoccupied; set-defined spawn budget per game (see §4) |
| `TerrainEffect` | `at: Vec2, effect: EffectType, triggers: u8, radius: u8` | tile walkable; creates a **zone** — caps standing in it (re-)acquire the effect each turn |
| `ToggleWall` | `at: Vec2, is_wall: bool` | design call: probably sepolia-testnet-later; changes layout walkability — powerful, needs strict budgets |

### 2.5 Meta ops

| Op | Fields | Notes |
|---|---|---|
| `PayEnergy` | `amount: u8` | abilities with dynamic costs (charge-up mechanics); core must pre-verify affordability |
| `DrawPower` | — | placeholder for a future deck/hand system — not in v1 |

## 3. Validation Rules (core-side, per op)

The core applies ops **in order** and validates each:

1. **Existence** — referenced cap exists, is alive, and (where noted) is in
   the actor's set/game.
2. **Ownership** — ops that modify enemy caps (Damage, Push, debuffs) are
   always legal; ops on friendly caps (Heal, Shield, buffs) are always
   legal. There is no "you can't touch the enemy" rule — that's the game.
3. **Physical legality** — movement targets must be walkable/unoccupied as
   of the op's application (ops apply sequentially; a Summon earlier in the
   list blocks a Teleport into that tile later).
4. **Clamping, never reverting** — Heal past max clamps to max; Shield
   stacks add; Damage past 0 kills. Ops fail *soft* (clamp) rather than
   reverting the whole ability — a partially-resolved ability beats a
   bricked turn.
5. **Budgets** — see §4. If an op exceeds a budget, it's dropped (with an
   event) rather than reverting.

## 4. Budgets — bounding set power without permissioning

Raw op counts could be abused ("deal 999 damage 100 times"). Budgets scale
with the set's declared costs:

- **Energy is the primary budget.** `activate_ability` receives the game's
  energy; the core charges `ability_cost` (from `CapType`) before applying
  ops. Sets that want big effects declare big costs.
- **Summon budget**: the `Set` model declares `max_summons_per_game` and
  `max_cap_types`; the core enforces them (a set can't flood the board).
- **Op count cap**: hard limit (e.g. 16 ops per ability) — enough for any
  sane composition, bounds gas, bounds griefing.
- **Per-target re-damage rule**: the same cap can be damaged at most N
  times per ability (N=4 to start) — prevents degenerate loops.

Budgets live on the `Set` model, set at registration, adjustable by
governance. This keeps the vocabulary open while the *quantities* stay
tuned.

## 5. SetEvent — the client animation stream

```cairo
pub enum SetEvent {
    Flavor { text: ByteArray },                 // "Pikeman braces!"
    EffectGained { cap_id: u64, effect: EffectType },
    DamageDealt { source: u64, target: u64, amount: u16 },
    PieceMoved { cap_id: u64, from: Vec2, to: Vec2 },
    Summoned { cap_id: u64, cap_type: u16, at: Vec2 },
}
```

Ops are state truth; events are presentation. The client plays events as an
animation queue. A set author who emits no events still works — the client
falls back to animating ops directly.

## 6. Worked examples (from the original set_zero, re-expressed)

**"Deal 4 damage to an enemy"** (Basic/Red):
```
ops:   [Damage { target: cap_at(target), amount: 4, source: Ability }]
events:[DamageDealt { .. }]
```

**"Shield an ally for 5"** (Basic/Yellow):
```
ops:   [Shield { target: cap_at(target), amount: 5 }]
```

**"Next attack +3"** (Mage/Red — "deal 1 self damage, buff an ally"):
```
ops:   [Damage { target: actor, amount: 1 },
        ApplyEffect { target: ally, effect: DamageBuff(3), triggers: 1 }]
```

**"Stun a target enemy"** (Mage/Blue):
```
ops:   [ApplyEffect { target: enemy, effect: Stun(1), triggers: 1 }]
```

**"Teleport-swap with an ally"** (new track-era piece):
```
ops:   [Swap { cap_a: actor, cap_b: ally }]
```

**"Gust — push the enemy 2 steps back along the track"** (new):
```
ops:   [Push { target: enemy, direction: computed_from_board, steps: 2 }]
```

**"Reinforce — summon a Militia at your deploy spot"** (new):
```
ops:   [Summon { cap_type: MILITIA_ID, at: deploy_spot }]
```

Every original ability maps onto this vocabulary. The vocabulary is also
already richer than set_zero needed — Push/Swap/Summon/Terrain are the
track-era additions.

## 7. What sets CANNOT do (by construction)

- Touch world storage, other games, or the token/ETH balance of anyone
- Declare they won; set the winner; end the game
- Spawn unlimited pieces (budgets)
- Act outside their ability's execution window
- Hide what they do (ops are the complete record, returned onchain)

## 8. Governance surface

| Layer | Who controls it | How it changes |
|---|---|---|
| Op vocabulary | Core upgrades | Governance proposal + vote |
| Budgets | `Set` model params | Governance (per-set or global) |
| EffectType list | Core upgrades | Governance proposal + vote |
| Individual sets | Their deployer | Deploy a new set contract; games opt in |

The vocabulary grows deliberately. A community wanting "charm: take control
of an enemy piece for a turn" proposes a `TakeControl` op; the core team
implements it with proper validation; governance ratifies. Meanwhile nobody
had to trust anybody's unvetted Cairo.

## 9. Implementation checklist

- [ ] `SetOp` enum + `SetOutput`/`AbilityContext`/`SetEvent` structs (models)
- [ ] `ISetInterface` v2: `activate_ability(ctx, target) -> SetOutput`
- [ ] Op applier in core: sequential validation + application (§3)
- [ ] Budget enforcement: `Set` model gains budget fields
- [ ] Zones (TerrainEffect) need `EffectTarget::Square` support in the tick loop
- [ ] Refactor set_zero to the pure-function style; port all 24 abilities
- [ ] Client: render `SetEvent` stream as animations; op-log in debug panel
- [ ] Simulate abilities client-side for preview (ops are pure — easy)
