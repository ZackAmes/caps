# Permissionless boards (rules 7)

Anyone can call `caps-boards.publish` and use the returned u64 board ID with
`caps-actions.create_game_with_board` or `create_solo_game_with_board`. There is no
owner gate, approval list, or requirement to ship a new client. Boards are immutable;
publishing an edited version produces a new ID. `GameBoard` binds each game to its
board. Built-in layouts 0–6 and existing games retain their original geometry.

The game menu's Community boards section loads any ID, browses recent publications,
and publishes JSON definitions with a live preview. Its template is the stylized
Duel Ring. The client and bot both decode the published definition with game-core.
The board ID is separate from the legacy u8 layout; published games use layout 255.

## Definition

```json
{
  "name": "A short path",
  "width": 15, "height": 15,
  "viewWidth": 8, "viewHeight": 10,
  "p1Goal": [0, 0], "p2Goal": [14, 14],
  "spots": [
    {"at": [0, 0], "position": [0, -3]},
    {"at": [8, 7], "position": [-2, 0], "energy": true},
    {"at": [14, 14], "position": [0, 3]}
  ],
  "connections": [
    {"from": [0, 0], "to": [8, 7], "via": [[-2, -2]]},
    {"from": [8, 7], "to": [14, 14]}
  ]
}
```

`at` identifies a logical spot. Rows/columns still refer to these coordinates.
`position` and `via` are independent visual coordinates, centered in the declared
visual extent. Rendering and picking use those positions in both 3D and 2D. Paths
are undirected; each connection is one step regardless of distance or waypoints.
Waypoints and line crossings do not create extra playable spots or adjacency.
Goals are also deployment spots. Energy spots feed the normal objective income.

The onchain ABI stores visual coordinates as unsigned thousandths from the extent's
upper-left corner. Edges refer to spot array indices. `encodeBoard`/`decodeBoard`
translate between that ABI and the JSON above. `get_publication(transaction_hash)`
recovers the board ID after submission, including when other users publish concurrently.

## Bounds and validation

Logical dimensions: 1–15 per axis. Spots: 2–64, with distinct logical and visual
positions. Connections: at most 128, no self edges or duplicate undirected edges.
Waypoints: at most 8 per connection. Visual extents: 1–65.535 units per axis;
positions must fit inside. Names: 1–64 bytes. Goals must be distinct playable spots.
The graph must be connected. The contract calculates shortest paths itself and stores
a packed distance table; callers cannot forge movement distances. The registry exposes
`get_geometry(layout, board_id)` for rule execution and owns the legacy map tables,
keeping the actions contract below the chain’s code-size limit. These resource
bounds keep publication and game transactions bounded. Publication does not certify
balance, readability, or fairness: players choose which board to play.

Permissionless board content is implemented here. Piece sets still use the existing
set registration and ability ABI; this change does not make all game rules arbitrary.

## Clocks

The client freezes the displayed banks while its turn transaction confirms and the
next state loads. A revert restores the running display; successful synchronization
replaces it with authoritative onchain time. The contract cannot observe browser
broadcast time, so time before transaction execution still counts. The existing
10-second increment remains. There is no client-supplied timestamp or pause request
that a player could exploit to stop the opponent's game.
