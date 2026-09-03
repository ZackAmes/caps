import { RpcProvider, CallData, Account, constants } from "starknet";
import type { AccountInterface } from "starknet";
import Controller from "@cartridge/controller";
import type { SessionPolicies } from "@cartridge/presets";
import { dojoConfig } from "./config";

const RPC = dojoConfig.rpcUrl;
const ACTIONS = dojoConfig.contracts.actions;

const provider = new RpcProvider({ nodeUrl: RPC });

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
      description: "CAPS — deploy caps, move, attack, and capture",
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
  setId: number;
  x: number | null;
  y: number | null;
  health: number;
  shield: number;
  stunnedTurns: number;
}

export interface ChainGame {
  id: number;
  player1: string;
  player2: string;
  layout: number;
  setId: number;
  turnCount: number;
  over: boolean;
  winner: string;
  energy: number;
  effectIds: number[];
  caps: ChainCap[];
}

/** A player's hand: deterministic cycle through their roster. */
export interface ChainHand {
  gameId: number;
  playerSlot: number;
  roster: number[];
  cursor: number;
  handSize: number;
  /** Cap ids currently visible in the window (server-computed). */
  window: number[];
}

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
  const f: string[] = raw as unknown as string[];
  if (!f || f.length === 0) return null;

  let i = 0;
  const option = num(f[i++]);
  if (option !== 0) return null;

  const hand: ChainHand = {
    gameId: num(f[i++]),
    playerSlot: num(f[i++]),
    roster: [],
    cursor: 0,
    handSize: 0,
    window: [],
  };
  // roster: Array<u64>
  const rosterLen = num(f[i++]);
  for (let k = 0; k < rosterLen; k++) hand.roster.push(num(f[i++]));
  hand.cursor = num(f[i++]);
  hand.handSize = num(f[i++]);
  // window: Span<u64>
  const windowLen = num(f[i++]);
  for (let k = 0; k < windowLen; k++) hand.window.push(num(f[i++]));
  return hand;
}

/** An active effect on the board. */
export interface ChainEffect {
  gameId: number;
  effectId: number;
  effectType: number; // EffectType enum index
  effectValue: number; // payload (damage/heal/etc)
  targetCapId: number;
  remainingTriggers: number;
}

/** Fetch all live effects for a game. Uses get_game's effect_ids + reads
 *  each effect model. For v1 we parse them from the game's effect_ids
 *  array via individual reads. */
export async function getEffects(gameId: number, effectIds: number[]): Promise<ChainEffect[]> {
  // v1: effects aren't exposed via a view — skip for now, the UI will
  // render them once a batched view lands.
  return [];
}

/** Piece definition fetched from the game's set contract. */
export interface CapTypeDef {
  id: number;
  name: string;
  description: string;
  maxHealth: number;
  attack: number;
  moveRange: number;
  attackRange: number;
  playCost: number;
  moveCost: number;
  abilityCost: number;
  abilityDescription: string;
  abilityTarget: number; // TargetType enum index
  abilityRange: Array<[number, number]>;
  passiveType: number; // PassiveType enum index (0 = None)
  passiveAmount: number;
  passiveCondition: number; // Condition enum index
  passiveRadius: number;
  passiveEffectType: number; // EffectType enum index (for Aura)
}

/** Target type labels for display. */
export const TARGET_LABELS: Record<number, string> = {
  0: 'None',
  1: 'Self',
  2: 'Ally',
  3: 'Enemy',
  4: 'Any piece',
  5: 'Any tile',
};

/** Passive type labels for display. */
export const PASSIVE_LABELS: Record<number, string> = {
  0: '',
  1: 'Aura',
  2: 'Tough',       // DamageReduction
  3: 'Berserk',     // ConditionalAttack
  4: 'Regen',       // Regeneration
  5: 'Swift',       // FreeFirstAttack
};

/** Condition labels for display. */
export const CONDITION_LABELS: Record<number, string> = {
  0: '',
  1: '3+ allies on board',
  2: 'has adjacent ally',
  3: 'enemy in range',
  4: 'low health',
  5: 'on enemy half',
};

/** Human-readable passive description from parsed passive fields. */
export function passiveLabel(def: CapTypeDef): string {
  const type = def.passiveType;
  if (type === 0) return '';
  const label = PASSIVE_LABELS[type] ?? 'Unknown';
  const cond = CONDITION_LABELS[def.passiveCondition];
  if (type === 2) return `${label}: -${def.passiveAmount} dmg taken`;
  if (type === 3) {
    return cond
      ? `${label}: +${def.passiveAmount} atk while ${cond}`
      : `${label}: +${def.passiveAmount} atk`;
  }
  return label;
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
  const f: string[] = raw as unknown as string[];
  if (!f || f.length === 0) return null;

  let i = 0;
  const option = num(f[i++]);
  if (option !== 0) return null;

  const id = num(f[i++]);
  // ByteArray: [len, chunk0..chunkN, pending_len, pending_data]
  const baLen = num(f[i++]);
  let name = "";
  for (let k = 0; k < baLen; k++) {
    name += BigInt(f[i++]).toString(16).padStart(64, "0")
      .replace(/00/g, "");
  }
  i++; // pending words len
  i++; // pending data
  const description = name; // second ByteArray parsed same way below
  const baLen2 = num(f[i++]);
  let desc = "";
  for (let k = 0; k < baLen2; k++) {
    desc += BigInt(f[i++]).toString(16).padStart(64, "0").replace(/00/g, "");
  }
  i++; // pending words len
  i++; // pending data

  const maxHealth = num(f[i++]);
  const attack = num(f[i++]);
  const moveRange = num(f[i++]);
  const attackRange = num(f[i++]);
  const playCost = num(f[i++]);
  const moveCost = num(f[i++]);
  const abilityCost = num(f[i++]);
  // third ByteArray: ability_description
  const baLen3 = num(f[i++]);
  let abilityDescription = "";
  for (let k = 0; k < baLen3; k++) {
    abilityDescription += BigInt(f[i++]).toString(16).padStart(64, "0")
      .replace(/00/g, "");
  }
  i++;
  i++;
  const abilityTarget = num(f[i++]);
  const rangeLen = num(f[i++]);
  const abilityRange: Array<[number, number]> = [];
  for (let k = 0; k < rangeLen; k++) {
    const rx = num(f[i++]);
    const ry = num(f[i++]);
    abilityRange.push([rx, ry]);
  }
  // Passive: struct { passive_type: PassiveType }
  // PassiveType is an enum — parse variant index + payload
  const passiveVariant = num(f[i++]);
  let passiveType = 0;
  let passiveAmount = 0;
  let passiveCondition = 0;
  let passiveRadius = 0;
  let passiveEffectType = 0;
  if (passiveVariant === 1) {
    // Aura: SetPassiveAura { effect: EffectType, radius: u8 }
    passiveType = 1;
    passiveEffectType = num(f[i++]);
    passiveRadius = num(f[i++]);
  } else if (passiveVariant === 2) {
    // DamageReduction: SetPassiveDamageReduction { amount: u16 }
    passiveType = 2;
    passiveAmount = num(f[i++]);
  } else if (passiveVariant === 3) {
    // ConditionalAttack: SetPassiveConditionalAttack { amount: u16, condition: Condition }
    passiveType = 3;
    passiveAmount = num(f[i++]);
    passiveCondition = num(f[i++]);
  } else if (passiveVariant === 4) {
    // Regeneration: SetPassiveRegeneration { amount: u16 }
    passiveType = 4;
    passiveAmount = num(f[i++]);
  } else if (passiveVariant === 5) {
    // FreeFirstAttack: unit variant, no payload
    passiveType = 5;
  }

  return {
    id,
    name,
    description: desc,
    maxHealth,
    attack,
    moveRange,
    attackRange,
    playCost,
    moveCost,
    abilityCost,
    abilityDescription,
    abilityTarget,
    abilityRange,
    passiveType,
    passiveAmount,
    passiveCondition,
    passiveRadius,
    passiveEffectType,
  };
}

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

/** Executes a call and waits for the transaction. Session txs are gasless
 *  once policies are approved; manual fallback opens the keychain modal. */
async function executeAndWait(call: {
  contractAddress: string;
  entrypoint: string;
  calldata: any;
}): Promise<string> {
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

export async function createGame(p2: string, layout: number = LAYOUT_PERIMETER_5X5): Promise<number> {
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: "create_game_with_layout",
    calldata: CallData.compile([p2, layout]),
  });
  return 1;
}

export async function createSoloGame(layout: number = LAYOUT_PERIMETER_5X5): Promise<number> {
  await executeAndWait({
    contractAddress: ACTIONS,
    entrypoint: "create_solo_game_with_layout",
    calldata: CallData.compile([layout]),
  });
  return 1;
}

const ACTION_VARIANT: Record<string, number> = { Play: 0, Move: 1, ClaimCapture: 2 };

export interface TurnAction {
  capId: number;
  kind: "Play" | "Move" | "ClaimCapture";
  x: number;
  y: number;
}

/** Check if an enemy cap at (x, y) is fully surrounded on the given layout.
 *  Towers are immune to capture; they must be destroyed. */
export function isSurroundedIn(
  caps: ChainCap[],
  layoutId: number,
  x: number,
  y: number
): boolean {
  const layout = getLayout(layoutId);
  const target = caps.find(c => c.x === x && c.y === y);
  if (!target || target.capType === 0) return false;

  const neighbors: Array<[number, number]> = [];
  for (let dx = -1; dx <= 1; dx++) {
    for (let dy = -1; dy <= 1; dy++) {
      if (dx === 0 && dy === 0) continue;
      const nx = x + dx;
      const ny = y + dy;
      if (nx >= 0 && nx < layout.width && ny >= 0 && ny < layout.height) {
        if (layout.isWalkable(nx, ny)) {
          neighbors.push([nx, ny]);
        }
      }
    }
  }
  if (neighbors.length === 0) return false;

  for (const [nx, ny] of neighbors) {
    const blocker = caps.find(c => c.x === nx && c.y === ny);
    if (!blocker) return false; // free escape tile
    if (blocker.owner === target.owner) return false; // friendly doesn't block
  }
  return true;
}

export function isSurrounded(game: ChainGame, x: number, y: number): boolean {
  return isSurroundedIn(game.caps, game.layout, x, y);
}

function isSurroundedLegacy(game: ChainGame, x: number, y: number): boolean {
  const layout = getLayout(game.layout);
  const target = game.caps.find(c => c.x === x && c.y === y);
  if (!target || target.capType === 0) return false;

  const neighbors: Array<[number, number]> = [];
  for (let dx = -1; dx <= 1; dx++) {
    for (let dy = -1; dy <= 1; dy++) {
      if (dx === 0 && dy === 0) continue;
      const nx = x + dx;
      const ny = y + dy;
      if (nx >= 0 && nx < layout.width && ny >= 0 && ny < layout.height) {
        if (layout.isWalkable(nx, ny)) {
          neighbors.push([nx, ny]);
        }
      }
    }
  }
  if (neighbors.length === 0) return false;

  for (const [nx, ny] of neighbors) {
    const blocker = game.caps.find(c => c.x === nx && c.y === ny);
    if (!blocker) return false; // free escape tile
    if (blocker.owner === target.owner) return false; // friendly doesn't block
  }
  return true;
}

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

function num(v: string): number {
  const n = Number(v);
  return typeof n === "number" && !Number.isNaN(n) ? n : 0;
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
    setId: num(f[i++]),
    turnCount: num(f[i++]),
    over: num(f[i++]) === 1,
    winner: f[i++],
    energy: 0,
    effectIds: [],
    caps: [],
  };

  // caps_ids: Array<u64>
  const idCount = num(f[i++]);
  for (let k = 0; k < idCount; k++) i++;
  // effect_ids: Array<u64>
  const effectCount = num(f[i++]);
  for (let k = 0; k < effectCount; k++) {
    game.effectIds.push(num(f[i++]));
  }
  // energy: u8, last_action_timestamp: u64
  game.energy = num(f[i++]);
  i++; // timestamp

  const capCount = num(f[i++]);
  for (let k = 0; k < capCount; k++) {
    const id = num(f[i++]);
    const owner = f[i++];
    const capType = num(f[i++]);
    const setId = num(f[i++]);
    const locVariant = num(f[i++]);
    let x: number | null = null;
    let y: number | null = null;
    if (locVariant === 1) {
      x = num(f[i++]);
      y = num(f[i++]);
    }
    const health = num(f[i++]);
    const shield = num(f[i++]);
    const stunnedTurns = num(f[i++]);
    game.caps.push({
      id, owner, capType, setId, x, y, health, shield, stunnedTurns,
    });
  }

  return game;
}
