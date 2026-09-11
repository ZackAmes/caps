# Mechanics foundation (rules v3)

Deployed with rules v4 to a fresh Sepolia world on September 8, 2026. The client
manifest and background bot use this deployment.

The branch now also includes [delayed abilities and the stack](DELAYED_ABILITIES.md),
which advance the protocol to v4. The passive/path semantics below remain applicable.

## Board topology and distance

`rules/boards.json` is the topology source of truth. Each path is an ordered list of
tiles. Consecutive entries create undirected edges. Shared tiles are junctions, where
pieces can choose any connected edge. Tiles that merely touch on the grid do not
become connected. Every edge costs exactly one step, even for diagonals, bends, or
future paths whose consecutive tiles have distant rendering coordinates.

Distance is the shortest connected route. Same valid tile: zero. Invalid or disconnected
tile: unreachable. Occupancy does not change distance; blocking and targeting ownership
are checked separately. Range does not imply line of sight or require intervening tiles
to be empty. A friendly-target ability includes self at distance zero; self-only targeting
requires the acting piece exactly. Normal movement still traverses exactly one edge and cannot pass through
a piece. Capture checks all directly connected neighbors. Cardinal Push operations
must also follow a valid edge; Teleport intentionally bypasses intermediate movement.

Examples: perimeter `(1,0)` to `(0,1)` costs two steps through the corner, not one.
Across the perimeter from `(2,0)` to `(2,4)` costs eight; on the cross it costs four.
On the X layout, `(0,0)` to `(1,1)` is one step.

The client and AI construct the graph from the JSON. `scripts/generate-boards.py`
generates contract distance tables from the same source to avoid onchain graph searches.
After editing paths, run the generator. `python3 scripts/generate-boards.py --check`
checks that the committed tables are current.

## Continuous passives

Each piece definition has a list of passives. A passive has:

- **Kind:** attack bonus, damage reduction, ability range bonus, energy generation, or regeneration.
- **Amount:** nonnegative integer.
- **Target:** self, other allies within N path steps, enemies within N steps, or all other pieces within N steps.
- **Conditions:** zero or more predicates on the source and board. All must hold.

An empty condition list means active for as long as the source is on the board.
Bench/captured/dead sources never contribute. Stun prevents actions, but does not turn
off board-presence passives. Auras exclude their source; add a self-targeted passive
when the source should also receive the bonus.

Conditions include friendly piece count (including self), another ally or enemy within
N path steps, health strictly below a percentage of base max health, being on the enemy
half, and another piece in the same row or column. Row/column conditions explicitly
select friendly, enemy, or either, always exclude self, and use grid coordinates.
Side identity uses player slot, not wallet address, so solo games behave correctly.

For example, a self attack bonus conditional on another friendly piece in the same row:

```ts
{
  kind: 'AttackBonus',
  amount: 2,
  target: { kind: 'SelfCap' },
  conditions: [{ kind: 'PieceInRow', relation: 'Ally' }]
}
```

Replace `conditions` with `[]` for an unconditional on-board bonus. Replace the target
with `{ kind: 'AlliesWithin', radius: 2 }` to make it a conditional aura instead.
Multiple conditions combine with AND; separate passive entries stack independently.

## Timing and stacking

Continuous bonuses are derived, not written as persistent effects. Conditions are
re-evaluated against current board state whenever a bonus is consumed, including
between queued actions and individual ability operations. Moving, killing, capturing,
or repositioning a source/prerequisite immediately changes later evaluations. There
are no stale aura buffs to clean up or refresh and no periodic aura stacking.

Every eligible source/entry contributes once. Bonuses add, saturating at 65,535.
Conditions read base board facts, not derived bonuses; there is no recursive activation.
Attack bonuses apply to contact attacks. Damage reduction applies before shields to
contact damage, active ability damage, and DOT. Ability range bonuses add path steps.

Economy and regeneration use the same eligibility engine but pay out at explicit times:
energy at the recipient owner's turn start, healing at their turn end. Losing a passive
does not claw back energy already earned or healing already received. Regeneration
eligibility is evaluated from the post-effect board before passive healing is applied.
The usual energy cap and maximum-health clamp still apply.

## Boundaries and compatibility

Timed status effects remain separate from passives. Their older unused enum variants
are not newly implemented by this change. No new roster is required to use the framework;
Set Zero keeps its existing roles and Generator is expressed as an unconditional passive.
The Blaster now uses a radius of three path steps instead of an incomplete offset list.

The client and AI share the passive evaluator and path logic. Active ability simulation
still implements Set Zero explicitly; arbitrary new active operations need preview
support. Movement/attack metadata does not grant multi-edge normal movement.

This changes the `CapType` set ABI (`passives` list and scalar path-step ability range).
`rules_version()` is now 4 after the stack extension; client and bot reject earlier versions. Deploy actions and Set Zero
together into a fresh v4 world, register the set, sync the manifest, then switch client
and bot. Use a separate checkpoint for the v4 bot. Do not upgrade only one contract or
silently reinterpret ongoing v2 games with the new path connections.

### Compact map tables

`generate-boards.py` packs sixteen byte-sized distances into each Cairo `u128` constant.
This keeps additional layouts below Starknet's class-size limit while preserving old
maps. `distance` extracts a single target for range/step checks; `distances` decodes a
row for neighbor enumeration. The value 255 still means unreachable. Client tests
compare every packed source/destination value against graph search on every layout.

### Connector squares and Duel Ring

Layout 6 is the new default: 28 playable spots with an evenly spaced eight-spot
inner ring and no center. Older layouts keep their existing rules.

Boards may define `connections` alongside legacy `paths`:

```json
{"from":[1,2],"to":[3,2],"via":[[2,2]]}
```

This connects the two endpoint spots in one movement step. `via` contains visual
connector squares, which may bend the path through several squares; pieces cannot
stop on them. Rendering uses every segment, while movement, range, surround capture,
and the bot use only the endpoint connection. A connector cannot overlap a playable
spot. Moving a connector changes the appearance without changing path distance.
The same definition generates contract distances and client/bot adjacency.
