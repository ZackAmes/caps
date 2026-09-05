export interface ChainCap {
  id: number;
  owner: string;
  playerSlot: number;
  capType: number;
  setId: number;
  x: number | null;
  y: number | null;
  health: number;
  shield: number;
  stunnedTurns: number;
  availableTurn: number;
  dead: boolean;
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
  winnerSlot: number;
  p1Energy: number;
  p2Energy: number;
  energy: number;
  effectIds: number[];
  caps: ChainCap[];
}

/** A player's hand: deterministic cycle through their roster. */
export interface ChainHand {
  gameId: number;
  playerSlot: number;
  roster: number[];
  handSize: number;
  /** Cap ids currently visible in the window (server-computed). */
  window: number[];
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

export interface TurnAction {
  capId: number;
  kind: "Play" | "Move" | "Ability";
  x: number;
  y: number;
}

