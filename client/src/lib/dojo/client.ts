import { CallData, type Call } from 'starknet';
import { decodeGame, decodeHand, decodeCapType } from './decode';
import { provider, ACTIONS } from './transport';
import { getAccount } from './account';
import { LAYOUT_PERIMETER_5X5 } from './board';
import type { ChainGame, ChainHand, CapTypeDef, TurnAction } from './types';

/** Fetch a player's hand (public — both hands visible). */
export async function getHand(
  gameId: number,
  playerSlot: number
): Promise<ChainHand | null> {
  const raw = await provider.callContract({
    contractAddress: ACTIONS,
    entrypoint: "get_hand",
    calldata: CallData.compile([gameId, playerSlot]),
  });
  return decodeHand(raw as unknown as string[]);
}

/** Fetch a piece definition from the game's set contract. */
export async function getCapType(
  gameId: number,
  capTypeId: number
): Promise<CapTypeDef | null> {
  const raw = await provider.callContract({
    contractAddress: ACTIONS,
    entrypoint: "get_cap_data",
    calldata: CallData.compile([gameId, capTypeId]),
  });
  return decodeCapType(raw as unknown as string[]);
}

/** Executes a call and waits for the transaction. Session txs are gasless
 *  once policies are approved; manual fallback opens the keychain modal. */
async function executeAndWait(call: Call): Promise<string> {
  const acc = getAccount();
  const res: any = await acc.execute(call);
  // With propagateSessionErrors=false, failures surface as thrown errors or
  // non-SUCCESS codes after the modal flow. Normalize both into a throw so
  // callers can log/display them.
  if (res && res.code && res.code !== "SUCCESS" && res.transaction_hash === undefined) {
    throw new Error(res.message ?? `Controller error (code ${res.code})`);
  }
  if (!res || !res.transaction_hash) {
    throw new Error("No transaction hash returned from Controller");
  }
  await provider.waitForTransaction(res.transaction_hash);
  return res.transaction_hash;
}

let rulesVerification: Promise<void> | null = null;
async function requireCurrentRules(): Promise<void> {
  // Share one check across concurrent game reads; retry on transient failures.
  rulesVerification ??= provider.callContract({
    contractAddress: ACTIONS, entrypoint: 'rules_version', calldata: [],
  }).then(version => {
    if (Number(version[0]) !== 2) throw new Error('This deployment uses an unsupported CAPS rules version.');
  }).catch((error: unknown) => {
    rulesVerification = null;
    throw error;
  });
  return rulesVerification;
}

export async function createGame(p2: string, layout: number = LAYOUT_PERIMETER_5X5): Promise<void> {
  await requireCurrentRules();
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: "create_game_with_layout",
    calldata: CallData.compile([p2, layout]),
  });
}

export async function createSoloGame(layout: number = LAYOUT_PERIMETER_5X5): Promise<void> {
  await requireCurrentRules();
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: "create_solo_game_with_layout",
    calldata: CallData.compile([layout]),
  });
}

const ACTION_VARIANT: Record<TurnAction["kind"], number> = {
  Play: 0,
  Move: 1,
  Ability: 2,
};

export async function takeTurn(gameId: number, actions: TurnAction[]): Promise<void> {
  const flat: (string | number)[] = [gameId, actions.length];
  for (const a of actions) {
    flat.push(a.capId, ACTION_VARIANT[a.kind], a.x, a.y);
  }
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: "take_turn",
    calldata: CallData.compile(flat),
  });
}

/** In-memory cache of cap type definitions per game (gameId -> typeId -> def). */
const capTypeCache: Map<number, Map<number, CapTypeDef>> = new Map();

export async function getCapTypeCached(gameId: number, capTypeId: number): Promise<CapTypeDef | null> {
  if (!capTypeCache.has(gameId)) {
    capTypeCache.set(gameId, new Map());
  }
  const cache = capTypeCache.get(gameId)!;
  if (cache.has(capTypeId)) {
    return cache.get(capTypeId)!;
  }
  const def = await getCapType(gameId, capTypeId);
  if (def) {
    cache.set(capTypeId, def);
  }
  return def;
}

export async function getGame(gameId: number): Promise<ChainGame | null> {
  await requireCurrentRules();
  const raw = await provider.callContract({
    contractAddress: ACTIONS,
    entrypoint: "get_game",
    calldata: CallData.compile([gameId]),
  });
  return decodeGame(raw as unknown as string[]);
}
