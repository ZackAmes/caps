import manifest from './manifest.json';

const actionsContract = (manifest as any).contracts.find((c: any) => c.tag === 'caps-actions');
const planeteloContract = (manifest as any).contracts.find((c: any) => c.tag === 'planetelo-planetelo');

export const dojoConfig = {
    // Sepolia network
    rpcUrl: 'https://api.cartridge.gg/x/starknet/sepolia/rpc/v0_9',
    chainId: 'SN_SEPOLIA' as const,

    // Deployed world address
    worldAddress: manifest.world.address as string,

    // Contract tags → addresses
    contracts: {
        actions: (actionsContract?.address ?? '') as string,
        planetelo: (planeteloContract?.address ?? '') as string,
    },

    // Cartridge Controller iframe URL (default)
    slot: 'cartridge' as const,
} as const;

export { manifest };
