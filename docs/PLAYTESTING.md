# Playtesting rules v6

The client and independent bot use the same September 9, 2026 upgrade of the same Sepolia world.
Old-world game IDs are separate and cannot be resumed in this client.

## Play against the bot

1. Open `/game`, choose **Start playing**, select a board, then **Play the bot**.
2. Drag a hand piece to your base to deploy, or drag a board piece to a highlighted
   connected square to move or attack. Tap/click selection also works in both views.
   Switch between **3D** and **2D** in the game menu.
3. Inspect a piece to read its ability and passive conditions. Abilities spend energy;
   deploying or moving spends the normal action. A Runner can grant an extra move.
4. **End turn** commits your plan. **Pass** ends a turn with no actions.
   Undoing a planned action also removes actions after it.
5. Wait for the bot. It polls every 15 seconds; transaction confirmation can take longer.
   The page refreshes while waiting. **Share game** in the menu shares the game; **Continue game**
   restores it after a refresh.

Both players' hands are public. The current test client intentionally uses one shared
human account, so testers should create separate games and avoid controlling the same
one simultaneously. The bot has its own account and processes challenges independently.
Its background service needs this host to stay awake and online.

## Mechanics to exercise

- Follow the visible connections on all six layouts. Each connection costs one step;
  diagonal connections count once, and touching squares without a connection are not adjacent.
- Reach the middle square of the opponent's back row to win.
- Surround a piece on every connected neighbor to capture it automatically. Check its
  two-owner-turn cooldown and eventual return to the hand.
- Inspect passive text and active status as pieces move. Energy income includes occupied
  side objectives and on-board Generators, up to a carried balance of five.
- Deploy a Blaster after cycling the initial hand. Announce its row attack with three
  energy. The orange threat markers (dashed rows in 2D) and pending list should appear in your plan; submitting announces
  it without immediate damage. The opponent gets a full turn to respond.
- Move out of a threatened row before ending the response turn. Pieces still in the row,
  including friendly pieces, take four damage subject to shield and damage reduction.
- Announce another delayed ability in response: the newer effect resolves first, and its
  delay holds up older entries. There are no out-of-turn priority prompts.

## Local checks

From the repo root:

```sh
bun install --frozen-lockfile
bun run test
bun run check
bun run --cwd client build
```

From `contracts`, use the project's Scarb 2.13.1 toolchain and run `scarb test`.
The tests cover passive conditions, graph distances, stack timing/order, preview legality,
hand rotation, capture cooldown, goal wins, and bot discovery/retry behavior.

For a stuck bot on this host, inspect `journalctl --user -u caps-bot.service -n 30`.
The active checkpoint is `bot/state/checkpoint-v6.json`; do not replace it with a checkpoint
from the old world. Account keys and bot state remain local and ignored by Git.

## 3D board

The main `/game` route renders the live board with Three.js through Threlte. The old
`/three` demo now redirects to the game. Both views use the same preview, selection,
ability targets, hand, and transaction submission; switching views keeps the current plan.
The camera stays fixed to preserve row orientation and make touch selection predictable.
WebGL initialization failure or context loss switches back to the 2D board automatically.
The view preference is stored locally. The 3D bundle loads separately from the core client.

## Stack responses and history

New games include a Negator at the end of the seven-piece roster. Cycle three pieces out
of the hand to make it available. Deploy it, choose Ability, then select an enemy effect
in the stack panel. Its two-energy negation is planned until you submit your turn.

Inspect pending effects to highlight their area. Verify newest-first order, the earliest
resolution turn including blockers above each entry, and disappearance after resolution
or negation. Open ↶ to read the opponent's latest actions and turn history
to inspect exact targets and outcomes. Old turns from before this upgrade have no records.

During submission, the preview should remain visible while the status progresses through
sending, confirming and updating. Try a slow connection: controls must stay locked after
a transaction is sent, without silently submitting again. Compare mobile portrait and a
wide desktop window; the board, stack, hand and fixed mobile submit button should remain
usable. Tap a hand piece to inspect it without deploying it.

### Duel Paths and orientation

Start a new game with **7x9 Duel Paths** (the previous default). Both P1 and P2 should see their
own base nearest the hand; in a bot game it must not rotate when the bot takes its turn.
Select a hand piece, tap your highlighted base, and submit. On a later turn the edge
between `(3,0)` and `(3,2)` counts as one step. Row effects can target row 8 (displayed
as row 9). Try a bot game on this map and load an older 5×5 game to verify both work.


### Timers and menus

New games start with **2:00** each. End a turn and verify only your bank is charged,
then increased by ten seconds. Let your clock expire in a bot game: the bot should
claim the win. A late action instead finalizes your loss without moving the piece.
When the opponent expires, the turn button becomes **Claim timeout win**. Check the
result panel and history both explain that the game ended on time.

Clocks stay visible above the board. The game menu contains sharing, refresh, view
settings, match state, and rules. Leaving for the lobby does not pause time. Verify
portrait mobile, short landscape, and desktop layouts: clocks and the hand should
stay visible without scrolling the game page. The lobby and menu panels can scroll.


### Corrected Duel grid

New matches default to layout 5, **7x5 Duel Grid**. Each back row has seven spots;
each side has five including corners. The nine inner spots form a 3×3 grid.
The four corners connect diagonally to the nearest inner corner. Each player's
right-of-goal spot connects to the middle spot of the nearest inner row; the two
approaches map onto each other under a 180-degree rotation. Goals connect only
along the back row. Every drawn edge still costs one step, regardless of its length.
Older 7x9 games retain layout 4 and their original paths.
