import type { ChainGame, ChainHand, CapTypeDef } from './client';
const num = (s: string): number => Number(BigInt(s));

export function decodeHand(f: string[]): ChainHand | null {
  if (!f || f.length === 0) return null;

  let i = 0;
  const option = num(f[i++]);
  if (option !== 0) return null;

  const hand: ChainHand = {
    gameId: num(f[i++]),
    playerSlot: num(f[i++]),
    roster: [],
    handSize: 0,
    window: [],
  };
  // roster: Array<u64>
  const rosterLen = num(f[i++]);
  for (let k = 0; k < rosterLen; k++) hand.roster.push(num(f[i++]));
  hand.handSize = num(f[i++]);
  // window: Span<u64>
  const windowLen = num(f[i++]);
  for (let k = 0; k < windowLen; k++) hand.window.push(num(f[i++]));
  return hand;
}

export function decodeCapType(f: string[]): CapTypeDef | null {
  if (!f || f.length === 0) return null;

  let i = 0;
  const option = num(f[i++]);
  if (option !== 0) return null;

  const id = num(f[i++]);
  const readText = () => {
    const count = num(f[i++]);
    const bytes: number[] = [];
    const append = (word: string, length: number) => {
      const hex = BigInt(word).toString(16).padStart(length * 2, '0');
      for (let k = 0; k < length; k++) bytes.push(parseInt(hex.slice(k * 2, k * 2 + 2), 16));
    };
    for (let k = 0; k < count; k++) append(f[i++], 31);
    const pending = f[i++];
    const pendingLength = num(f[i++]);
    append(pending, pendingLength);
    return new TextDecoder().decode(new Uint8Array(bytes));
  };
  const name = readText();
  const desc = readText();
  const maxHealth = num(f[i++]);
  const attack = num(f[i++]);
  const moveRange = num(f[i++]);
  const attackRange = num(f[i++]);
  const playCost = num(f[i++]);
  const moveCost = num(f[i++]);
  const abilityCost = num(f[i++]);
  const abilityDescription = readText();
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
    if (passiveEffectType !== 0) i++; // effect magnitude
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
    if ([1, 3, 4].includes(passiveCondition)) i++; // condition threshold
  } else if (passiveVariant === 4) {
    // Regeneration: SetPassiveRegeneration { amount: u16 }
    passiveType = 4;
    passiveAmount = num(f[i++]);
  } else if (passiveVariant === 6) {
    passiveType = 6;
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

export function decodeGame(f: string[]): ChainGame | null {
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
    winnerSlot: num(f[i++]),
    p1Energy: 0,
    p2Energy: 0,
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
  game.p1Energy = num(f[i++]);
  game.p2Energy = num(f[i++]);
  i++; // next effect id
  i++; // timestamp

  const capCount = num(f[i++]);
  for (let k = 0; k < capCount; k++) {
    const id = num(f[i++]);
    const owner = f[i++];
    const playerSlot = num(f[i++]);
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
    const availableTurn = num(f[i++]);
    game.caps.push({
      id, owner, playerSlot, capType, setId, x, y, health, shield, stunnedTurns, availableTurn, dead: locVariant === 2,
    });
  }

  return game;
}

