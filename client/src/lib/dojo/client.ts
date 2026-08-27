import { RpcProvider, CallData } from "starknet";
import type { AccountInterface } from "starknet";
import Controller from "@cartridge/controller";
import { dojoConfig } from "./config";

const RPC = dojoConfig.rpcUrl;
const ACTIONS = dojoConfig.contracts.actions;

const provider = new RpcProvider({ nodeUrl: RPC });

let controller: Controller | null = null;
let account: AccountInterface | null = null;

// Static per-type stats matching the contract's cap_stats().
// [maxHealth, attack, attackRange(chebyshev), moveRange(chebyshev)]
export const CAP_STATS: Record<number, [number, number, number, number]> = {
  0: [12, 2, 1, 1],
  1: [8, 2, 1, 1],
  2: [8, 3, 1, 2],
  3: [6, 3, 2, 1],
};

export interface ChainCap {
  id: number;
  owner: string; // felt as decimal string
  capType: number;
  x: number | null;
  y: number | null;
  health: number;
  maxHealth: number;
  attack: number;
}

export interface ChainGame {
  id: number;
  player1: string;
  player2: string;
  turnCount: number;
  over: boolean;
  winner: string;
  lastFrame: number;
  caps: ChainCap[];
}

export async function connect(): Promise<AccountInterface> {
  controller = new Controller({ rpcUrl: RPC });
  account = (await controller.connect()) ?? null;
  return account!;
}

export function isConnected(): boolean {
  return account !== null;
}

export function getAccount(): AccountInterface {
  if (!account) throw new Error("Not connected");
  return account;
}

/** Creates a game; caller is player1, `p2` is the opponent address. */
export async function createGame(p2: string): Promise<number> {
  const acc = getAccount();
  const res = await acc.execute({
    contractAddress: ACTIONS,
    entrypoint: "create_game",
    calldata: CallData.compile([p2]),
  });
  await provider.waitForTransaction(res.transaction_hash);
  return 1; // game id is global.games_counter+1; we refetch below if needed
}

const ACTION_VARIANT: Record<string, number> = { Play: 0, Move: 1, Attack: 2 };

export interface TurnAction {
  capId: number;
  kind: "Play" | "Move" | "Attack";
  x: number;
  y: number;
}

/** Submits a turn composed of Play/Move/Attack actions. */
export async function takeTurn(gameId: number, actions: TurnAction[]): Promise<void> {
  const acc = getAccount();
  const flat: (string | number)[] = [gameId, actions.length];
  for (const a of actions) {
    flat.push(a.capId, ACTION_VARIANT[a.kind], a.x, a.y);
  }
  const res = await acc.execute({
    contractAddress: ACTIONS,
    entrypoint: "take_turn",
    calldata: CallData.compile(flat),
  });
  await provider.waitForTransaction(res.transaction_hash);
}

function num(v: string): number {
  const n = Number(v);
  return typeof n === "number" && !Number.isNaN(n) ? n : 0;
}

/** Fetches and parses a game from get_game. Returns null if the game doesn't exist. */
export async function getGame(gameId: number): Promise<ChainGame | null> {
  const raw = await provider.callContract({
    contractAddress: ACTIONS,
    entrypoint: "get_game",
    calldata: CallData.compile([gameId]),
  });
  const f: string[] = raw as unknown as string[];
  if (!f || f.length === 0) return null;

  let i = 0;
  // Option variant: 0 = Some, 1 = None
  const option = num(f[i++]);
  if (option !== 0) return null;

  const game: ChainGame = {
    id: num(f[i++]),
    player1: f[i++],
    player2: f[i++],
    turnCount: num(f[i++]),
    over: num(f[i++]) === 1,
    winner: f[i++],
    lastFrame: 0,
    caps: [],
  };

  // game.caps_ids array
  const idCount = num(f[i++]);
  for (let k = 0; k < idCount; k++) i++;

  game.lastFrame = num(f[i++]);

  // caps array
  const capCount = num(f[i++]);
  for (let k = 0; k < capCount; k++) {
    const id = num(f[i++]);
    const owner = f[i++];
    const capType = num(f[i++]);
    const locVariant = num(f[i++]);
    let x: number | null = null;
    let y: number | null = null;
    if (locVariant === 1) {
      x = num(f[i++]);
      y = num(f[i++]);
    }
    const health = num(f[i++]);
    const stats = CAP_STATS[capType] ?? CAP_STATS[1];
    game.caps.push({ id, owner, capType, x, y, health, maxHealth: stats[0], attack: stats[1] });
  }

  return game;
}
