# CAPS contracts

Dojo 1.8 / Cairo 2.13.1 contracts for the CAPS tactical board game.

See [current rules](../docs/GAME_DESIGN.md) for gameplay and balance values.

## Validate

From this directory, using Scarb 2.13.1:

```sh
scarb build
scarb test
```

The tests deploy a Dojo test world and exercise the actual actions contract and reference set. They do not submit network transactions or spend Sepolia funds. `test_game.ts` is a separate legacy manual network smoke script.

## Deploying this rules version

This is a breaking model/ABI change. Deploy into a fresh world (use a new profile seed), deploy the updated standalone Set Zero contract, register it with the actions contract as set id 0, and copy the resulting world manifest to `client/src/lib/dojo/manifest.json`. The checked-in client manifest targets the v2 world deployed September 5, 2026. Never point the new client at old game state.

The existing `scripts/deploy.sh` migrates the selected profile and syncs its manifest; it does not choose a fresh seed or register Set Zero for you. Review the target profile before using it.

The hardcoded Sepolia test account is intentionally retained for the current development workflow.
