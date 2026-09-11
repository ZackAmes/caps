# Frontend state and action history (rules v6)

This is an additive upgrade of the September 8 world. Existing games, piece IDs,
boards, hands and pending abilities are preserved. New games have seven pieces per
side, including a Negator. Existing games keep their original roster.

## Stack targeting

`ActionType::StackAbility(u64)` is appended to the action enum (variant 3). Its payload
is a stable effect ID, not board coordinates or an index into the stack. The original
Play, Move and Ability encodings are unchanged. `TargetType` adds AnyPending (6),
EnemyPending (7) and AllyPending (8). Core validation checks the source is on board,
not stunned, unused this turn, has enough energy, and the target exists with the right
side relation. Stack targets have no spatial range. Sets implement
`activate_stack_ability(ctx, target_id)` and return the same validated SetOps as before.

The reference Negator (type 6, 6 HP, 1 attack, 2 energy) negates an enemy entry immediately
during its owner's normal turn. It consumes that piece's activation, not the normal
move/deploy action. Select the Negator, activate its ability, then choose an eligible
entry in the stack panel. Negation is previewed until the turn is submitted. Stale IDs
revert instead of accidentally targeting another entry. The bot generates the same
explicit stack-target actions.

The stack panel shows source, owner, announcement turn, raw readiness, resolution order,
and the earliest resolution boundary allowed by all newer entries. Announcements added
later can change that boundary. Inspect an effect to highlight its footprint and see
currently affected pieces. Eligibility is re-evaluated when the effect resolves.

## History without Torii

`TurnRecord` is keyed by `(game_id, turn)` and is written atomically with the turn. It
stores submitted actions in order, before/after piece snapshots, before/after stacks,
actual stack resolution order, and the acting player's energy before/after spending.
`get_turn(game_id, turn)` returns an optional record. Passes are recorded too.

The client reads four records at a time over RPC. It shows the opponent's latest actions
next to the board and expandable results in turn history. Move/attack targets are shown
exactly as submitted; final positions, health, shield, capture/death and stun changes
come from the recorded snapshots. Records are available only for turns after this upgrade;
missing earlier records are not reconstructed or presented as exact history.

## Submission and refresh

The planned board stays visible through sending, confirmation and synchronization.
Controls stay locked once a transaction hash exists until a successful receipt and a
newer game snapshot are observed. A timeout does not automatically resubmit the turn.
Reverted transactions unlock the retained plan. RPC reads have deadlines and retry on
subsequent polls. Refresh is also available manually.

The client reads the game, related hands/stack/definitions, then the game again. If the
turn changed, the mixed snapshot is discarded and re-read. Opponent updates and updates
from another tab are checked every five seconds, and on returning to the tab. History
loads separately so a history failure does not prevent board play.

## Viewport game screen

The match fills the dynamic viewport with a Three.js board, compact status controls,
four hand slots, undo and end-turn controls. It does not scroll the page. The lobby
still scrolls normally. Safe areas and a separate short landscape layout keep controls
within the viewport. The board uses the smaller available stage dimension so it stays
fully framed as selected-piece details open above the hand.

Drag a hand piece onto your base to deploy, or drag a board piece to a highlighted
destination to move or attack. Invalid drops cancel. Tap a hand piece to inspect it,
then Deploy or tap the highlighted base; tap-to-select/move also remains available.
Touch and mouse share pointer capture, with cancellation on capture loss, window blur,
or a new game snapshot. Gestures only queue actions; End turn submits them.
The 3D picker uses the active camera and converts the drop into canonical map coordinates. Ability descriptions and
passive conditions appear only for hovered/selected pieces. Hover cards float without
resizing the board. Piece symbols match the hand, and health remains visible. Three.js
movement interpolates over 180 ms and respects reduced-motion preferences.

Stack, history and menu information live in native modal dialogs with close buttons and
Escape support. Long optional details can scroll within those dialogs. The stack button
shows its count; a pending-effect chip shows the next resolution timing. Activating a
Negator opens stack targeting; selecting an effect for inspection closes the dialog and
highlights its footprint. Full recorded actions remain available in history. The menu
contains refresh, sharing, opponent hand, cooldowns, queued actions and the 2D fallback.

Validation: type checks, production build and the shared client/bot suite pass. Browser
visual/touch verification is unavailable in the current environment and remains needed.

New-game map selection starts at 7×9 Duel Paths and is independent of resumed games.
Loading an old match no longer changes the default bot challenge map. The lobby map
selector still allows an explicit alternative.


## Match clocks

The coherent RPC snapshot includes `get_clock`, which returns both clock storage and
the current chain timestamp. The client anchors it to `performance.now()` and ticks
locally, avoiding dependence on the device wall-clock setting. The display is an
estimate; the contract determines expiry at transaction execution. Timeout claims
use the same pending/confirmation/state-refresh flow as turns and an expected-turn
guard. A timeout advances `turn_count` and sets `GameClock.timed_out_slot`, so the
result UI and history distinguish it from a goal win without inventing a turn record.

## Board artwork

`client/src/lib/game/board-art.ts` owns visual spot positions and path segments.
Duel Ring uses free-positioned circular nodes, a square inner ring, and direct
corner strokes. Logical connector squares remain in the rules but are not rendered
as tiles or mandatory bends. Changing artwork does not change path distances or
canonical action/ability coordinates. Both 2D and Three.js use the same artwork;
3D picking finds the rendered node and returns its logical coordinates rather than
rounding the pointer to a grid square. Grid labels and empty grid tiles are hidden.
