import { decodeClock } from '@caps/game-core/clock';
import { consistentSnapshot } from '../game/sync';
import { beginMoveIntent } from '@caps/game-core/move-intent';
import { encodeActions } from '@caps/game-core/encode';
import { CallData, type Call } from 'starknet';
import { decodeGame, decodeHand, decodeCapType, decodeStack, decodeTurnRecord } from '@caps/game-core/decode';
import { provider, ACTIONS } from './transport';
import { getAccount } from './account';
import { decodeBoard, encodeBoard, type BoardDraft, type PublishedBoard } from '@caps/game-core/published-board';
import { dojoConfig } from './config';
import { getLayout, LAYOUT_PERIMETER_5X5 } from '@caps/game-core/board';
import type { ChainGame, ChainHand, CapTypeDef, TurnAction } from '@caps/game-core/types';

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
export type TransactionProgress = (stage: 'confirming' | 'syncing', hash: string) => void;
async function executeAndWait(call: Call, progress?: TransactionProgress): Promise<string> {
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
  progress?.('confirming', res.transaction_hash);
  const receipt = await provider.waitForTransaction(res.transaction_hash, {retryInterval:1000});
  if (!receipt.isSuccess()) throw new Error('Transaction reverted');
  progress?.('syncing', res.transaction_hash);
  return res.transaction_hash;
}

let rulesVerification: Promise<void> | null = null;
async function requireCurrentRules(): Promise<void> {
  // Share one check across concurrent game reads; retry on transient failures.
  rulesVerification ??= provider.callContract({
    contractAddress: ACTIONS, entrypoint: 'rules_version', calldata: [],
  }).then(version => {
    if (Number(version[0]) !== 7) throw new Error('This deployment uses an unsupported CAPS rules version.');
  }).catch((error: unknown) => {
    rulesVerification = null;
    throw error;
  });
  return rulesVerification;
}

export async function createGame(p2: string, layout: number = LAYOUT_PERIMETER_5X5, boardId = 0): Promise<void> {
  await requireCurrentRules();
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: boardId ? "create_game_with_board" : "create_game_with_layout",
    calldata: CallData.compile([p2, boardId || layout]),
  });
}

export async function createSoloGame(layout: number = LAYOUT_PERIMETER_5X5, boardId = 0): Promise<void> {
  await requireCurrentRules();
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: boardId ? "create_solo_game_with_board" : "create_solo_game_with_layout",
    calldata: CallData.compile([boardId || layout]),
  });
}

export async function takeTurn(gameId: number, expectedTurn: number, actions: TurnAction[], progress?: TransactionProgress): Promise<void> {
  const intent = beginMoveIntent(dojoConfig.toriiUrl, dojoConfig.worldAddress, getAccount(), gameId, expectedTurn, actions,
    error => console.warn('Move preview unavailable', error));
  let hash: string | undefined;
  try {
    await executeAndWait({
      contractAddress: ACTIONS,
      entrypoint: 'take_turn_if_current',
      calldata: CallData.compile([gameId, expectedTurn, ...encodeActions(actions)]),
    }, (stage, txHash) => {
      hash = txHash;
      if (stage === 'confirming') intent.broadcast(txHash);
      progress?.(stage, txHash);
    });
  } catch (error) {
    // Unknown receipt/network failures can still land; those hints expire naturally.
    if (!hash || (error instanceof Error && error.message === 'Transaction reverted')) intent.cancel(hash);
    throw error;
  }
}

export async function getGameCount(): Promise<number> {
  const response = await provider.callContract({ contractAddress: ACTIONS, entrypoint: 'get_game_count', calldata: [] });
  return Number(response[0]);
}

export async function findLatestGameForPlayer(address: string): Promise<number | null> {
  for (let end = await getGameCount(); end > 0; end -= 20) {
    const ids = Array.from({ length: Math.min(20, end) }, (_, i) => end - i);
    const games = await Promise.all(ids.map(id => getGame(id)));
    const found = games.find(game => game && [game.player1, game.player2].some(p => BigInt(p) === BigInt(address)));
    if (found) return found.id;
  }
  return null;
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

export async function getStack(gameId: number) {
  await requireCurrentRules();
  return decodeStack(await provider.callContract({ contractAddress: ACTIONS, entrypoint: 'get_stack', calldata: CallData.compile([gameId]) }));
}

export async function getTurnRecord(gameId: number, turn: number) {
  return decodeTurnRecord(await provider.callContract({contractAddress:ACTIONS,entrypoint:'get_turn',calldata:CallData.compile([gameId,turn])}));
}
export async function transactionState(hash: string): Promise<'pending'|'confirmed'|'reverted'> {
  try {
    const receipt = await provider.getTransactionReceipt(hash);
    if (receipt.isReverted()) return 'reverted';
    return receipt.isSuccess() && ['ACCEPTED_ON_L2','ACCEPTED_ON_L1'].includes(receipt.finality_status) ? 'confirmed' : 'pending';
  } catch (error) {
    if (typeof error === 'object' && error && 'code' in error && error.code === 29) return 'pending';
    throw error;
  }
}
/** Reject mixed snapshots if a turn advances between independent RPC reads. */
export async function getGameSnapshot(id: number, minimumTurn = 0) {
  const {game,details} = await consistentSnapshot(() => getGame(id), async game => {
    const slot = game.turnCount % 2;
    const [hand, otherHand, stack, definitions, clock, layout] = await Promise.all([
      getHand(id,slot), getHand(id,1-slot), getStack(id),
      Promise.all([...new Set(game.caps.map(c=>c.capType))].map(type=>getCapTypeCached(id,type))),
      getClock(id), getGameLayout(game),
    ]);
    if (!hand || !otherHand || definitions.some(d=>!d)) throw new Error('Incomplete game snapshot; retrying is safe.');
    return {hand,otherHand,stack,clock,layout,definitions:new Map(definitions.map(d=>[d!.id,d!]))};
  }, minimumTurn);
  return {game,...details};
}

export async function getClock(gameId:number) {
  const clock=decodeClock(await provider.callContract({contractAddress:ACTIONS,entrypoint:'get_clock',calldata:CallData.compile([gameId])}));
  return {clock,receivedAt:performance.now()};
}
export async function claimTimeout(gameId:number,turn:number,progress?:TransactionProgress) {
  await executeAndWait({contractAddress:ACTIONS,entrypoint:'claim_timeout',calldata:CallData.compile([gameId,turn])},progress);
}

const boards = new Map<number, PublishedBoard>();
async function boardCall(entrypoint:string, calldata:(string|number)[] = []) {
  if (!dojoConfig.contracts.boards) throw new Error('Board registry is unavailable on this deployment');
  return provider.callContract({contractAddress:dojoConfig.contracts.boards,entrypoint,calldata:CallData.compile(calldata)});
}
export async function getPublishedBoard(id:number):Promise<PublishedBoard> {
  if (!Number.isSafeInteger(id) || id < 1) throw new Error('Enter a valid board ID');
  if (boards.has(id)) return boards.get(id)!;
  const board = decodeBoard(await boardCall('get_board',[id]));
  if (!board) throw new Error(`Board #${id} does not exist`);
  boards.set(id,board); return board;
}
export async function getBoardCount() { return Number((await boardCall('get_board_count'))[0]); }
export async function publishBoard(draft:BoardDraft) {
  const hash = await executeAndWait({contractAddress:dojoConfig.contracts.boards,entrypoint:'publish',calldata:CallData.compile(encodeBoard(draft))});
  const id = Number((await boardCall('get_publication',[hash]))[0]);
  return getPublishedBoard(id);
}
async function getGameLayout(game:ChainGame) {
  if (game.layout !== 255) return getLayout(game.layout);
  const [id] = await provider.callContract({contractAddress:ACTIONS,entrypoint:'get_game_board',calldata:CallData.compile([game.id])});
  return (await getPublishedBoard(Number(id))).layout;
}
