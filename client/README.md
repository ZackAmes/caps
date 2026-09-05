# CAPS client

Svelte 5 client for CAPS on Starknet Sepolia. See [game rules](../docs/GAME_DESIGN.md).

```sh
bun install
bun run dev
bun run check
bun test tests
bun run build
```

The hardcoded test account in `src/lib/dojo/account.ts` is intentional while Controller is unavailable on Sepolia. An optional `VITE_CONTROLLER_RPC_KEY` configures browser RPC access.

## Code layout

- `dojo/types.ts`: game, piece, hand, ability and action data types.
- `dojo/board.ts`: track layouts and bounded movement geometry; no wallet or RPC dependency.
- `dojo/decode.ts`: tested Cairo response decoders.
- `dojo/preview.ts`: deterministic turn preview for the reference set.
- `dojo/account.ts`: current test account and retained Controller connection path.
- `dojo/transport.ts`: shared RPC provider and deployed actions address.
- `dojo/client.ts`: contract reads, transactions and piece-definition cache.
- `dojo/labels.ts`: display text for passive abilities.
- `routes/game/+page.svelte`: interaction state and game UI.

The client manifest is synced from the deployed Sepolia world. Pushing `main` triggers the repository's Vercel production deployment.

## Remaining cleanup opportunities

The game page still combines board rendering, pointer interaction and lobby UI. Split those components separately from rule changes. Game discovery still probes the first 40 game ids; replace this with a dedicated creation event or lookup endpoint before the test world grows beyond that range. Preview execution supports the reference set; new sets need a general ability-preview interface.
