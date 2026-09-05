import manifest from './manifest.json';

const actionsContract = manifest.contracts.find((c) => c.tag === 'caps-actions');

if (!actionsContract) throw new Error('Client manifest is missing caps-actions');

// ── Single RPC: Cartridge Starknet Sepolia ──
// The Controller requires the Cartridge RPC (its session execution posts the
// custom method cartridge_addExecuteOutsideTransaction, unsupported elsewhere).
// Using it for everything keeps auth, sessions, and paymaster on one path.
// Access is authorized with the Cartridge RPC token (sk_...) via ?key=.
const CARTRIDGE_RPC = 'https://api.cartridge.gg/x/starknet/sepolia/rpc/v0_9';

const rpcKey = import.meta.env.VITE_CONTROLLER_RPC_KEY;
const rpcUrl = rpcKey ? `${CARTRIDGE_RPC}?key=${rpcKey}` : CARTRIDGE_RPC;

export const dojoConfig = {
    // Sepolia network
    rpcUrl,
    chainId: 'SN_SEPOLIA' as const,

    // Deployed world address
    worldAddress: manifest.world.address as string,

    // Contract tags → addresses
    contracts: {
        actions: actionsContract.address,
    },
} as const;

export { manifest };
