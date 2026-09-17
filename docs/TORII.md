# Local Torii

CAPS uses Torii 1.8.16 on Zack's machine, indexing the existing Sepolia world from
block **14760367**. The indexer needs RPC access, not a signing key. Its database is
persisted in `~/.local/share/caps/torii`; restarting resumes indexing.

- Local HTTP/GraphQL: `http://127.0.0.1:8081/graphql`
- Local WebSocket: `ws://127.0.0.1:8081/graphql/ws`
- Public endpoint: `client/src/lib/dojo/torii.json`
- Configuration: `contracts/torii_sepolia.toml`
- Pinned binary: `~/.local/share/caps/bin/torii`
- Service templates: `ops/systemd/`

`caps-torii.service` runs the indexer. `caps-torii-tunnel.service` exposes its HTTP
port through a temporary Cloudflare HTTPS tunnel. The bot connects over localhost;
the Vercel client uses the public endpoint. SQL playground access is disabled.
CORS allows the production client and local Vite development origins.

```sh
systemctl --user status caps-torii caps-torii-tunnel caps-bot
journalctl --user -u caps-torii.service -n 30
journalctl --user -u caps-bot.service -n 30
systemctl --user restart caps-torii.service
```

The tunnel URL may change when **the tunnel** restarts (including a reboot). To find
it, inspect `journalctl --user -u caps-torii-tunnel.service`. Update `url` in
`client/src/lib/dojo/torii.json`, then redeploy the client. A named tunnel/domain can
replace this later. `VITE_TORII_URL` overrides the checked-in public URL, and
`BOT_TORII_URL` controls the bot endpoint. Set either to an empty string to disable
subscriptions. For local frontend development, set `VITE_TORII_URL=http://127.0.0.1:8081`.

The machine must remain awake and connected. User services are enabled at login;
lingering controls whether they also start before login. This is a development
hosting arrangement, with RPC polling available when Torii or its tunnel is down.

## Update flow

`game-core/torii` implements the GraphQL WebSocket subscription shared by the client
and bot. It filters Game models, deduplicates updates, sends heartbeats, reconnects
with backoff, and cleans up on shutdown/navigation. The client watches its current
game; the bot wakes for games involving its account. Bot ticks remain serialized,
including notifications arriving while a tick is in flight.

Torii indexes preconfirmed changes. Notifications trigger a fresh, coherent RPC
snapshot rather than directly applying partial indexed model writes. This removes
the normal polling wait without trusting stale indexer state for gameplay. The
client retries briefly if RPC has not caught up, and keeps its five-second polling
fallback. The bot keeps its periodic fallback for discovery, timeouts, and receipts.
Torii doesn't change onchain timing or shorten chain execution itself.

To inspect indexed games in the GraphQL explorer:

```graphql
{
  capsGameModels(first: 20) {
    totalCount
    edges { node { id turn_count over } }
  }
}
```

## Signed move previews and confirmed events

Submitting a turn publishes a signed `caps-MoveIntent` to Torii through the unary
gRPC-web `/world.World/PublishMessage` endpoint on the same HTTP URL. Both the
client and bot publish: submitted (`status=0`), broadcast with transaction hash
(`1`), and cancelled/reverted (`2`). Torii verifies the account signature and
monotonically increasing millisecond timestamps. No additional ports are exposed.
Preview publication is best effort and never blocks a transaction.

The client subscribes to `entityUpdated` for these intents. It checks the world,
game, current turn and active player, then validates actions with the shared game
preview rules. Opponent pieces and the ability stack appear immediately with a
pending label. Hints expire after 60 seconds, and cancellation, a reverted receipt,
or advancing authoritative state removes them. Hints never advance the turn,
change clocks, declare a winner, or make the bot act. RPC snapshots and existing
`TurnRecord` history remain authoritative; polling still works without Torii.

An accepted onchain turn emits `caps-MoveCommitted`, keyed by game and completed
turn, containing the same `MoveIntent` structure and encoded actions, with
`status=3`, the real transaction hash, and the block timestamp in milliseconds.
Torii indexes it as an event message (`eventMessageUpdated`), separate from signed
model entities. Consumers must never treat a relayed status value as confirmation.
Reverted actions and submissions that lose on time do not emit a committed move.
The onchain system does not read or write the offchain preview model.
