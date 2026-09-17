import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export interface BotConfig {
  rpcUrl: string;
  toriiUrl: string;
  address: string;
  privateKey: string;
  actionsAddress: string;
  boardsAddress: string;
  pollMs: number;
  statePath: string;
}

export function loadConfig(env = process.env): BotConfig {
  const required = (key: string) => {
    const value = env[key];
    if (!value) throw new Error(`Missing ${key}; provision the bot account or configure bot/.env`);
    return value;
  };
  const manifestPath = env.BOT_MANIFEST_PATH ?? resolve(import.meta.dir, '../../client/src/lib/dojo/manifest.json');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const actionsAddress = env.BOT_ACTIONS_ADDRESS ?? manifest.contracts.find((c: { tag: string }) => c.tag === 'caps-actions')?.address;
  if (!actionsAddress) throw new Error('Missing actions contract');
  const pollMs = Number(env.BOT_POLL_MS ?? 15000);
  if (!Number.isFinite(pollMs) || pollMs < 1000) throw new Error('BOT_POLL_MS must be at least 1000');
  const config = {
    toriiUrl: env.BOT_TORII_URL ?? '',
    rpcUrl: required('BOT_RPC_URL'), address: required('BOT_ADDRESS'), privateKey: required('BOT_PRIVATE_KEY'),
    actionsAddress, boardsAddress: env.BOT_BOARDS_ADDRESS ?? manifest.contracts.find((c:{tag:string})=>c.tag === "caps-boards")?.address ?? "", pollMs, statePath: env.BOT_STATE_PATH ?? resolve(import.meta.dir, '../state/checkpoint.json'),
  };
  for (const value of [config.address, config.privateKey, config.actionsAddress]) {
    if (!/^0x[0-9a-fA-F]+$/.test(value) || BigInt(value) === 0n) throw new Error('Account, key, and contract must be nonzero hex values');
  }
  return config;
}
