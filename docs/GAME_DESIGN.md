# CAPS — implemented rules (v6)

See [MECHANICS_FOUNDATION.md](MECHANICS_FOUNDATION.md) for passive/path semantics and [DELAYED_ABILITIES.md](DELAYED_ABILITIES.md) for the ability stack. This document is the source of truth for the September 2026 prototype. The former tower, paid movement and manual capture rules are retired.

## Objective and board

Reach the center of the opponent's back row with any piece. The original four 5×5 layouts use bases `(2,0)` and `(2,4)`. The new default 7×9 Duel Paths map uses `(3,0)` and `(3,8)`. Each player wins by reaching the other base; deployment is still at your own base. Reaching a goal ends the match immediately, including movement caused by an ability. There are no towers or elimination-based win checks.

Deployment uses your own base square, which must be empty. Movement is one edge along an explicitly connected path. Grid proximity alone does not connect tiles. Moving into an enemy attacks: shields absorb damage first, and the attacker takes the square only if the enemy dies. Friendly pieces block movement. Death removes a piece permanently; capture is different.

## Turns and abilities

Each turn has one normal action: deploy or move/attack. Neither costs energy. Passing is allowed, including when the player has no usable pieces.

Abilities spend their listed energy independently of the normal action. Each piece can activate at most once per turn. Abilities can grant:

- Extra moves: usable only for move/attack.
- Extra actions: usable for deploy or move/attack.

Move-only allowances are spent before general actions. All unused allowances expire at turn end. The reference Runner spends 2 energy to grant one extra move. An ability may precede or follow the normal action, including an ability on a newly deployed piece.

The contract applies each queued action to the latest state, resolves victory/capture, then handles the next action. A queued action after victory is invalid. The client drops subsequent queued actions when an earlier action is removed, because they may depend on it.

## Delayed abilities

Abilities may announce effects on a public stack. A delay of one grants the opponent a full response turn. Ready effects resolve newest first; an unready top blocks older effects. Targets are selected from the board at resolution, and announced effects survive source removal. Responses use normal turns. See the delayed-ability document for full ordering and counter rules.

## Automatic surround capture

After each action or ability finishes, capture any piece whose **every directly connected path neighbor** is occupied by opposing pieces. Empty or friendly adjacent squares provide an escape. All captures are determined from the same board snapshot and applied simultaneously. No capture action exists.

Captured pieces return to their owner's bench at full health, without shields, stuns or attached effects, and move to the back of that owner's draw queue. They cannot deploy during the owner's next two turns and become eligible on the third. For example, a P2 piece captured on global turn 0 cannot deploy on P2 turns 1 and 3, and becomes eligible on turn 5. A piece captured during its own turn skips its next two owner turns too.

## Public deterministic hand

New games start with a seven-piece roster per side, including the Negator; existing games retain their six-piece roster. The first four eligible bench pieces in queue order form the hand. There is no randomness or hidden information; both hands are publicly readable and displayed.

Playing a chosen piece moves it to the back of the queue. The hand refills immediately from eligible bench pieces while preserving the other choices. Board pieces, dead pieces and pieces on capture cooldown are skipped. They never occupy or block hand slots. Captured pieces rejoin at the back and must finish their cooldown before being eligible to draw. Eligibility does not guarantee immediate inclusion if four earlier pieces fill the hand.

## Energy: initial balance values

These values are a first playable balance pass, not fixed design commitments:

- Start with 0 stored energy; gain **1** at the start of each owner turn, including the first.
- Gain **1** for each side-midpoint objective occupied by your piece: `(0,2)` and `(4,2)`.
- Each on-board Generator provides **1** additional energy per owner turn.
- Unspent energy carries over separately for each side, capped at **5**.
- Only abilities spend energy.

Control means current occupation at turn start; control is not retained after leaving a square. Energy is prepared and persisted before a player acts, so the client and contract use the same budget. Energy attached to a piece applies to that piece's side, including in solo mode.

## Reference roster

| Type | Piece | HP | Attack | Ability | Cost |
| --- | --- | --- | --- | --- | --- |
| 0 | Generator | 5 | 1 | Passive: +1 income while on board | — |
| 1 | Striker | 6 | 2 | Deal 2 damage to an enemy | 2 |
| 2 | Guardian | 10 | 1 | Give an ally 3 shield | 2 |
| 3 | Medic | 7 | 1 | Heal an ally 3, capped at its real maximum HP | 2 |
| 4 | Blaster | 5 | 1 | After one opponent turn, deal 4 damage to all pieces in a chosen row | 3 |
| 5 | Runner | 6 | 2 | Gain one extra move this turn | 2 |
| 6 | Negator | 6 | 1 | Negate one enemy pending effect, regardless of distance | 2 |

Ability ranges are shortest-path step counts, identical for both sides and independent of grid distance or intervening pieces. Self-targeted abilities require the acting piece's own square.

## Development and compatibility

The hardcoded Sepolia test account remains intentional while Controller is unavailable. Solo games use that account for both sides, but every piece has an explicit player slot; ownership checks, targeting, colors, income, cooldowns and victory use the slot correctly.

The v4 foundation changes the set ABI, board connections, and adds stored pending abilities. Use a fresh v4 world and games, deploy actions and Set Zero together, register set 0, and sync the manifest before switching the client and bot. `rules_version()` returns 5; the client and bot reject incompatible deployments.

The client manifest and bot target the September 8, 2026 **v4** Sepolia world (`0x64b3825d2b0343b2b33778a2426dcfb54d8968e5078e6ecc140eed10889af99`). Set Zero is registered as set 0. Old v2 games remain in the previous world and are not migrated.

The client previews the reference set's actions and abilities. The onchain contract is authoritative; arbitrary future sets will need corresponding preview support.

Rules v5 adds stack-target abilities and an RPC-readable turn journal in the same world. New games have seven pieces per side; existing rosters are preserved. See [Frontend state and history](FRONTEND_STATE.md).

## Map definitions and view

`rules/boards.json` defines dimensions, bases, energy spaces and explicit paths. The
contract geometry tables are generated from that file. Existing layouts 0–3 are
unchanged; layout 4 adds a 7×9 Duel-inspired map with branching flanks and a central
diamond. It is a prototype, not a reproduction of Pokémon Duel’s entry-point rules.
Connected segments count one step even when their grid coordinates are far apart.

The client rotates the board 180° for P1 so each player's own base is always at the
bottom, beside their hand. P2 uses the canonical orientation. This is presentation
only: stored coordinates, row targets and action history do not change. Solo mode
follows the active side. Both 3D and the 2D fallback share this convention.


## Match clocks (v6)

Each player starts with 120 seconds. Only the active player's time runs, beginning at
match creation. Each completed, non-winning turn adds 10 seconds to that player's
remaining time; abilities and extra moves within the turn do not add increments.
The contract charges elapsed block time when the turn executes, including network
confirmation delays. Invalid turns revert and do not reset or increment the clock.

At zero seconds the active player loses. A late turn records the loss without executing
its actions or resolving pending effects. The opponent can call `claim_timeout(game_id,
expected_turn)` to end an expired game; the turn guard prevents a claim from crossing
into a later turn. Timeout clears the stack, advances the terminal turn count, and records
the losing slot in `GameClock`; it does not create a fabricated action journal entry.

`GameClock` is separate from `Game`, so existing matches remain compatible. Matches
created before v6 receive fresh clocks on their next successful turn. Missing clocks
cannot be claimed as expired. Completed clocks remain frozen. There is no pause when
leaving the page, and practice mode has separate clocks for its two sides.


## Duel grid (layout 5)

The default board uses a seven-spot back row and five-spot side tracks including
corners, surrounding a 3×3 inner grid (29 total spots). Corners connect to inner
corners. The spot to each player's right of their goal connects to the center of
the nearest inner row, giving 180-degree rotational symmetry. Goals are `(3,0)`
and `(3,4)`; side energy spaces are `(0,2)` and `(6,2)`. Inner columns are 1, 3, 5:
the two-coordinate horizontal gap remains a single path step. Layout 4 is preserved
for existing matches; creating new games defaults to layout 5 in the client.
