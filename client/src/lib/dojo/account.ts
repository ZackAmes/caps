import { Account, constants } from 'starknet';
import type { AccountInterface } from 'starknet';
import Controller from '@cartridge/controller';
import type { SessionPolicies } from '@cartridge/presets';
import { provider, ACTIONS } from './transport';
import { dojoConfig } from './config';
const RPC = dojoConfig.rpcUrl;

let controller: Controller | null = null;
let account: AccountInterface | null = null;
// Dev mode: bypass Controller entirely with a raw funded test account.
// Sepolia test key only — fine to hardcode since the account holds nothing
// of value. Remove before any mainnet/public launch.
const DEV_ADDRESS = "0x694182a014b39855a1b139961a3f39e7d4b43527b30d892a630d66a2abe3780";
const DEV_PRIVATE_KEY = "0x0430638cc3ef026ad7a74d9ad143bfc15bf303cea0be1c972ab1f280c90a531a";
const devMode = true;

// Session policies: user approves once, then create/turn calls run gaslessly
// via the Controller paymaster without a manual approval modal each turn.
const policies: SessionPolicies = {
  contracts: {
    [ACTIONS]: {
      description: "CAPS — deploy pieces, move, and activate abilities",
      methods: [
        { name: "Create Game", entrypoint: "create_game" },
        { name: "Create Game with Layout", entrypoint: "create_game_with_layout" },
        { name: "Create Solo Game", entrypoint: "create_solo_game" },
        { name: "Create Solo Game with Layout", entrypoint: "create_solo_game_with_layout" },
        { name: "Take Turn", entrypoint: "take_turn" },
        { name: "Get Game", entrypoint: "get_game" },
        { name: "Upgrade", entrypoint: "upgrade" },
      ],
    },
  },
};

export function isDevMode(): boolean {
  return devMode;
}

export async function connect(): Promise<AccountInterface> {
  if (devMode) {
    // Dev account path: no Controller, no sessions, no paymaster.
    // Gas is paid directly from the dev account's STRK.
    account = new Account({
      provider,
      address: DEV_ADDRESS!,
      signer: DEV_PRIVATE_KEY!,
    });
    return account;
  }

  controller = new Controller({
    // Chain config is required — without it Controller defaults to mainnet.
    chains: [{ rpcUrl: RPC }],
    defaultChainId: constants.StarknetChainId.SN_SEPOLIA,
    policies,
    // Do NOT propagate session errors: when gasless sponsorship fails
    // (e.g. AVNU paymaster outage), the keychain modal must open so the
    // user can execute manually with their own STRK balance. Propagating
    // errors would skip that fallback entirely.
    propagateSessionErrors: false,
    // Modal (default) shows the full manual-execution flow on failure —
    // more reliable on mobile than an auto-dismissing toast.
    errorDisplayMode: "modal",
  });
  const acc = await controller.connect();
  if (!acc) {
    account = null;
    throw new Error("Sign-in was cancelled or failed");
  }
  account = acc;
  return acc;
}

export function getAccount(): AccountInterface {
  if (!account) throw new Error("Not connected");
  return account;
}

