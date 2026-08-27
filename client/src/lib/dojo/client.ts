import { RpcProvider, CallData } from "starknet";
import type { AccountInterface } from "starknet";
import Controller from "@cartridge/controller";
import { dojoConfig } from "./config";

const RPC = dojoConfig.rpcUrl;
const ACTIONS = dojoConfig.contracts.actions;

const provider = new RpcProvider({ nodeUrl: RPC });

let controller: Controller | null = null;
let account: AccountInterface | null = null;

export const CAP_STATS: Record<number, [number, number, number, number]> = {
  0: [12, 2, 1, 1],
  1: [8, 2, 1, 1],
  2: [8, 3, 1, 2],
  3: [6, 3, 2, 1],
};

// Layout types
export const LAYOUT_PERIMETER_5X5 = 0;
export const LAYOUT_CROSS_5X5 = 1;
export const LAYOUT_DIAGONAL_X_5X5 = 2;
export const LAYOUT_DIAMOND_5X5 = 3;

export interface LayoutConfig {
  id: number;
  name: string;
  description: string;
  width: number;
  height: number;
  p1Deploy: [number, number];
  p2Deploy: [number, number];
  isWalkable: (x: number, y: number) => boolean;
}

export const LAYOUTS: Record<number, LayoutConfig> = {
  [LAYOUT_PERIMETER_5X5]: {
    id: LAYOUT_PERIMETER_5X5,
    name: "5x5 Perimeter Track",
    description: "Outer boundary track only",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) => x === 0 || x === 4 || y === 0 || y === 4,
  },
  [LAYOUT_CROSS_5X5]: {
    id: LAYOUT_CROSS_5X5,
    name: "5x5 Track + Cross",
    description: "Perimeter plus center cross lanes",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) =>
      x === 0 || x === 4 || y === 0 || y === 4 || x === 2 || y === 2,
  },
  [LAYOUT_DIAGONAL_X_5X5]: {
    id: LAYOUT_DIAGONAL_X_5X5,
    name: "5x5 Diagonal X Track",
    description: "Perimeter with diagonal corner-to-corner routes through center",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) =>
      x === 0 || x === 4 || y === 0 || y === 4 || x === y || x + y === 4,
  },
  [LAYOUT_DIAMOND_5X5]: {
    id: LAYOUT_DIAMOND_5X5,
    name: "5x5 Diamond Diagonal",
    description: "Perimeter with inner diamond diagonal ring connecting edge midpoints",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) => {
      const isPerimeter = x === 0 || x === 4 || y === 0 || y === 4;
      const isDiamond =
        (x === 2 && y === 1) || (x === 3 && y === 2) || (x === 2 && y === 3) || (x === 1 && y === 2);
      return isPerimeter || isDiamond;
    },
  },
};

export function getLayout(layoutId: number): LayoutConfig {
  return LAYOUTS[layoutId] ?? LAYOUTS[LAYOUT_PERIMETER_5X5];
}

/** Check if moving from `from` to `to` is a valid 1-step move (including diagonals) on the given layout */
export function isValidStep(layoutId: number, from: [number, number], to: [number, number]): boolean {
  const layout = getLayout(layoutId);
  if (!layout.isWalkable(from[0], from[1]) || !layout.isWalkable(to[0], to[1])) {
    return false;
  }
  if (from[0] === to[0] && from[1] === to[1]) {
    return false;
  }
  const dx = Math.abs(from[0] - to[0]);
  const dy = Math.abs(from[1] - to[1]);
  // 1-step orthogonal or diagonal
  return dx <= 1 && dy <= 1;
}

export interface ChainCap {
  id: number;
  owner: string;
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
  layout: number;
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

export function getAddress(): string {
  return getAccount().address;
}

export async function createGame(p2: string, layout: number = LAYOUT_PERIMETER_5X5): Promise<number> {
  const acc = getAccount();
  const res = await acc.execute({
    contractAddress: ACTIONS,
    entrypoint: "create_game_with_layout",
    calldata: CallData.compile([p2, layout]),
  });
  await provider.waitForTransaction(res.transaction_hash);
  return 1;
}

export async function createSoloGame(layout: number = LAYOUT_PERIMETER_5X5): Promise<number> {
  const acc = getAccount();
  const res = await acc.execute({
    contractAddress: ACTIONS,
    entrypoint: "create_solo_game_with_layout",
    calldata: CallData.compile([layout]),
  });
  await provider.waitForTransaction(res.transaction_hash);
  return 1;
}

const ACTION_VARIANT: Record<string, number> = { Play: 0, Move: 1, Attack: 2 };

export interface TurnAction {
  capId: number;
  kind: "Play" | "Move" | "Attack";
  x: number;
  y: number;
}

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

export async function getGame(gameId: number): Promise<ChainGame | null> {
  const raw = await provider.callContract({
    contractAddress: ACTIONS,
    entrypoint: "get_game",
    calldata: CallData.compile([gameId]),
  });
  const f: string[] = raw as unknown as string[];
  if (!f || f.length === 0) return null;

  let i = 0;
  const option = num(f[i++]);
  if (option !== 0) return null;

  const game: ChainGame = {
    id: num(f[i++]),
    player1: f[i++],
    player2: f[i++],
    layout: num(f[i++]),
    turnCount: num(f[i++]),
    over: num(f[i++]) === 1,
    winner: f[i++],
    lastFrame: 0,
    caps: [],
  };

  const idCount = num(f[i++]);
  for (let k = 0; k < idCount; k++) i++;

  game.lastFrame = num(f[i++]);

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
