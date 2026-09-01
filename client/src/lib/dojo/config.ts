import manifest from './manifest.json';

const actionsContract = (manifest as any).contracts.find((c: any) => c.tag === 'caps-actions');

// Alchemy Starknet Sepolia RPC (versioned endpoint).
// The API key is the final path segment. Set RPC_KEY in Vercel env or a local .env file.
const ALCHEMY_BASE = 'https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10';
const FALLBACK_RPC = 'https://api.cartridge.gg/x/starknet/sepolia/rpc/v0_9';

const rpcKey = (import.meta.env as any).RPC_KEY as string | undefined;
const rpcUrl = rpcKey ? `${ALCHEMY_BASE}/${rpcKey}` : FALLBACK_RPC;

export const dojoConfig = {
    // Sepolia network
    rpcUrl,
    chainId: 'SN_SEPOLIA' as const,

    // Deployed world address
    worldAddress: manifest.world.address as string,

    // Contract tags → addresses
    contracts: {
        actions: (actionsContract?.address ?? '') as string,
    },
} as const;

export { manifest };
