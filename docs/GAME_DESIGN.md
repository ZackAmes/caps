# CAPS — current rules (v2)

This document is the source of truth for the September 2026 prototype. The former tower, paid movement and manual capture rules are retired.

## Objective and board

Reach the center of the opponent's back row with any piece. Player 1 starts at `(2,0)` and wins at `(2,4)`; Player 2 starts at `(2,4)` and wins at `(2,0)`. All four 5×5 track layouts share these bases. Reaching a goal ends the match immediately, including movement caused by an ability. There are no towers or elimination-based win checks.

Deployment uses your own base square, which must be empty. Movement is one orthogonal or diagonal step to an adjacent walkable tile. Moving into an enemy attacks: shields absorb damage first, and the attacker takes the square only if the enemy dies. Friendly pieces block movement. Death removes a piece permanently; capture is different.

## Turns and abilities

Each turn has one normal action: deploy or move/attack. Neither costs energy. Passing is allowed, including when the player has no usable pieces.

Abilities spend their listed energy independently of the normal action. Each piece can activate at most once per turn. Abilities can grant:

- Extra moves: usable only for move/attack.
- Extra actions: usable for deploy or move/attack.

Move-only allowances are spent before general actions. All unused allowances expire at turn end. The reference Runner spends 2 energy to grant one extra move. An ability may precede or follow the normal action, including an ability on a newly deployed piece.

The contract applies each queued action to the latest state, resolves victory/capture, then handles the next action. A queued action after victory is invalid. The client drops subsequent queued actions when an earlier action is removed, because they may depend on it.

## Automatic surround capture

After each action or ability finishes, capture any piece whose **every adjacent walkable square** is occupied by opposing pieces. Empty or friendly adjacent squares provide an escape. All captures are determined from the same board snapshot and applied simultaneously. No capture action exists.

Captured pieces return to their owner's bench at full health, without shields, stuns or attached effects, and move to the back of that owner's draw queue. They cannot deploy during the owner's next two turns and become eligible on the third. For example, a P2 piece captured on global turn 0 cannot deploy on P2 turns 1 and 3, and becomes eligible on turn 5. A piece captured during its own turn skips its next two owner turns too.

## Public deterministic hand

Each side starts with a six-piece roster. The first four eligible bench pieces in queue order form the hand. There is no randomness or hidden information; both hands are publicly readable and displayed.

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
| 4 | Blaster | 5 | 1 | Deal 4 damage to an enemy in its targeting pattern | 3 |
| 5 | Runner | 6 | 2 | Gain one extra move this turn | 2 |

Ability ranges are absolute offset patterns mirrored across both axes; they are the same for both sides. Self-targeted abilities require the acting piece's own square.

## Development and compatibility

The hardcoded Sepolia test account remains intentional while Controller is unavailable. Solo games use that account for both sides, but every piece has an explicit player slot; ownership checks, targeting, colors, income, cooldowns and victory use the slot correctly.

These changes alter the Game, Cap, Hand and set ABI. Use a **fresh world and fresh games**, redeploy Set Zero, register it as set 0, and sync the new manifest before running this client against Sepolia. `rules_version()` returns 2; the client checks it before creating/loading a game to avoid interpreting an old deployment with the new schema. Existing deployed games are not migrated by these code changes.

Deployed September 5, 2026 on Sepolia: world `0x76621c09cb35987c3760b3bd22573327305ccfdb45aa10493f284552505e92d`. The client manifest targets this v2 world.

The client previews the reference set's actions and abilities. The onchain contract is authoritative; arbitrary future sets will need corresponding preview support.
