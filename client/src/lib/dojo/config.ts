import manifest from './manifest.json';

const actionsContract = (manifest as any).contracts.find((c: any) => c.tag === 'caps-actions');

// ── App read/write RPC: Alchemy Starknet Sepolia (versioned endpoint) ──
// The API key is the final path segment. Set RPC_KEY in Vercel env or a local .env file.
const ALCHEMY_BASE = 'https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10';
const CARTRIDGE_RPC = 'https://api.cartridge.gg/x/starknet/sepolia/rpc/v0_9';

const alchemyKey = (import.meta.env as any).RPC_KEY as string | undefined;
const rpcUrl = alchemyKey ? `${ALCHEMY_BASE}/${alchemyKey}` : CARTRIDGE_RPC;

// ── Controller RPC: MUST be a Cartridge RPC endpoint ──
// The Controller's session execution posts the custom method
// cartridge_addExecuteOutsideTransaction, which only Cartridge RPC
// understands (Alchemy rejects it as an unsupported method).
// Access is authorized with the Cartridge RPC token (sk_...) via ?key=.
const cartridgeKey = (import.meta.env as any).CONTROLLER_RPC_KEY as string | undefined;
const controllerRpcUrl = cartridgeKey ? `${CARTRIDGE_RPC}?key=${cartridgeKey}` : CARTRIDGE_RPC;

export const dojoConfig = {
    // Sepolia network
    rpcUrl,
    controllerRpcUrl,
    chainId: 'SN_SEPOLIA' as const,

    // Deployed world address
    worldAddress: manifest.world.address as string,

    // Contract tags → addresses
    contracts: {
        actions: (actionsContract?.address ?? '') as string,
    },
} as const;

export { manifest };
