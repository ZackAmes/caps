# CAPS bot

The checked-in manifest targets the September 9, 2026 rules v7 Sepolia deployment.
The background bot runs from `~/caps` with a separate v7 checkpoint.

A standalone Sepolia player with its own account. Anyone can challenge the address in
[account.public.json](account.public.json), or use **Play against Bot** in the game lobby.
The worker polls every 15 seconds and processes one transaction at a time across its games.
It runs independently of the website, while its host is awake and online.

## Run

From the repository root, run `bun install --frozen-lockfile`. Copy `bot/.env.example`
to `bot/.env` and supply a **separate** deployed, funded Sepolia account. Then:

```sh
cd bot
bun run start
# One discovery/turn poll, useful for diagnostics:
bun run once
```

To provision a new single-key account using the existing Sepolia profile as a test-token
funding source, run `bun src/provision.ts ../contracts/dojo_sepolia.toml 5` from `bot/`.
This persists its key before funding/deployment, writes the ignored `.env`, and updates
`account.public.json`. Rerunning reuses the account and tops up its test STRK balance.
Never commit `.env` or `state/`. Keep both when restarting or moving this worker.

For a local user service (adjust paths if the checkout is not `~/caps`):

```sh
mkdir -p ~/.config/systemd/user
cp deploy/caps-bot.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now caps-bot.service
journalctl --user -u caps-bot.service -n 30
```

Use `systemctl --user restart caps-bot` after updating code. User services normally start
on login; continuous operation across logout requires user lingering. A sleeping or
offline machine cannot play turns. For an always-online server, install Bun, clone the
repo, transfer the ignored credentials/checkpoint securely, and run the same service.
Stop the old worker before starting the replacement.

## Change the game or strategy

- `src/worker.ts` handles discovery, turn ownership, retrying, and checkpoints. It has no
  board logic. `src/ports.ts` defines its adapter and strategy interfaces.
- `src/game/v7.ts` owns ABI reads, transaction encoding, and constructing a v7 position.
  Unsupported rules versions, sets, and layouts are rejected rather than guessed.
- `src/strategies/greedy.ts` is a pure function. Replace it and select the replacement in
  `src/main.ts` to change play style without touching accounts or polling.
- `packages/game-core` contains types, decoding, encoding, board geometry, and the shared
  reference-set turn simulator used by both the website and bot. Change this together
  with contract rules and regression tests. The contract remains authoritative.

The first policy searches up to three actions with a beam width of eight. It favors
winning, advancing toward the goal, defending an immediate threat, material, energy
objectives, and Generators. It can combine abilities with movement and forecasts pending stack damage when choosing a response. It is deterministic
and has no opponent lookahead, training, or hidden information.

Discovery walks `get_game_count` in batches of 20, retains unfinished challenges, and
round-robins active games. Failed reads do not advance the discovery checkpoint. Pending
transaction hashes survive restarts; `take_turn_if_current` also atomically rejects a
stale expected turn, protecting against duplicate actions after ambiguous RPC failures.
The checkpoint is scoped to chain, actions contract, bot address, and rules version.
Use a new `BOT_STATE_PATH` when changing these. A process lock prevents two local workers
using the same checkpoint; it does not coordinate multiple hosts.

Tests: `bun test bot/tests client/tests` and `bun run check` from the repo root. Contract
regressions run with Scarb 2.13.1 in `contracts/`.

The v6 clock upgrade keeps the same world. The local service uses
`state/checkpoint-v6.json`, migrated from v5 while stopped so active games and pending
transactions are retained. On opponent turns the adapter reads the authoritative clock
and claims expired games. Claims share the worker's transaction tracking and nonce
serialization with ordinary turns. The strategy remains independent of clock/ABI code.

Rules 7 adds permissionless boards. The adapter loads the game’s board ID and published
definition from the configured manifest’s registry; strategies still receive a pure
LayoutConfig. BOT_BOARDS_ADDRESS can override the registry address. The live service
uses checkpoint-v7.json, preserving discovery and pending transactions from v6.

Torii subscription setup and local service commands are in [docs/TORII.md](../docs/TORII.md).
Game updates involving the bot wake its serialized worker immediately. Periodic
polls still handle reconnects, timeouts, and transaction confirmation.
