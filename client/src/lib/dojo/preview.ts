import type { LayoutConfig } from './board';
import type { ChainCap, ChainGame, ChainHand, CapTypeDef, TurnAction } from './types';

export function handIds(roster: number[], caps: ChainCap[], turn: number, size = 4): number[] {
  return roster.filter(id => {
    const c = caps.find(c => c.id === id);
    return c && !c.dead && c.x === null && c.availableTurn <= turn;
  }).slice(0, size);
}

export function surrounded(caps: ChainCap[], layout: LayoutConfig, c: ChainCap): boolean {
  if (c.x === null || c.y === null || c.dead) return false;
  let neighbors = 0;
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) {
    if (!dx && !dy) continue;
    const x = c.x + dx, y = c.y + dy;
    if (x < 0 || y < 0 || x >= layout.width || y >= layout.height || !layout.isWalkable(x, y)) continue;
    neighbors++;
    const other = caps.find(p => !p.dead && p.x === x && p.y === y);
    if (!other || other.playerSlot === c.playerSlot) return false;
  }
  return neighbors > 0;
}

/** Preview the reference set. The contract remains authoritative on submission. */
export function previewTurn(game: ChainGame, hand: ChainHand | null, defs: Map<number, CapTypeDef>, layout: LayoutConfig, queue: TurnAction[]) {
  const caps = game.caps.map(c => ({ ...c }));
  let energy = game.energy, actions = 1, moves = 0;
  let winnerSlot: number | null = game.over ? game.winnerSlot : null;
  const usedAbilities = new Set<number>();
  let roster = [...(hand?.roster ?? [])];
  const requeue = (id: number) => { roster = [...roster.filter(x => x !== id), id]; };
  const damage = (c: ChainCap, amount: number) => {
    const absorbed = Math.min(amount, c.shield);
    c.shield -= absorbed;
    c.health = Math.max(0, c.health - (amount - absorbed));
    if (!c.health) { c.dead = true; c.x = null; c.y = null; }
  };
  for (const a of queue) {
    if (winnerSlot !== null) throw new Error('The goal has already been reached');
    const c = caps.find(c => c.id === a.capId);
    const def = c && defs.get(c.capType);
    if (!c || !def || c.dead || c.playerSlot !== game.turnCount % 2) throw new Error('Piece unavailable');
    if (c.stunnedTurns) throw new Error('Piece is stunned');
    const target = caps.find(c => !c.dead && c.x === a.x && c.y === a.y);
    if (a.kind !== 'Ability') {
      if (a.kind === 'Move' && moves > 0) moves--;
      else if (actions > 0) actions--;
      else throw new Error('No normal actions left; an ability can grant extra moves');
    }
    if (a.kind === 'Play') {
      if (!handIds(roster, caps, game.turnCount, hand?.handSize).includes(c.id)) throw new Error('Piece not in hand or on cooldown');
      const spot = c.playerSlot === 0 ? layout.p1Deploy : layout.p2Deploy;
      if (a.x !== spot[0] || a.y !== spot[1] || target) throw new Error('Deploy square occupied or invalid');
      c.x = a.x; c.y = a.y; requeue(c.id);
    } else if (a.kind === 'Move') {
      if (c.x === null || c.y === null || !layout.isWalkable(a.x, a.y) || a.x < 0 || a.y < 0 || a.x >= layout.width || a.y >= layout.height || Math.max(Math.abs(a.x - c.x), Math.abs(a.y - c.y)) !== 1) throw new Error('Move one adjacent step');
      if (target) {
        if (target.playerSlot === c.playerSlot) throw new Error('Friendly piece occupies that square');
        const td = defs.get(target.capType);
        damage(target, Math.max(0, def.attack - (td?.passiveType === 2 ? td.passiveAmount : 0)));
        if (target.dead) { c.x = a.x; c.y = a.y; }
      } else { c.x = a.x; c.y = a.y; }
    } else {
      if (c.x === null || c.y === null || !def.abilityTarget) throw new Error('Ability requires a board piece');
      if (usedAbilities.has(c.id)) throw new Error('Each piece can activate once per turn');
      if (energy < def.abilityCost) throw new Error(`Not enough energy (need ${def.abilityCost}, have ${energy})`);
      if (def.abilityTarget === 1) {
        if (c.x !== a.x || c.y !== a.y) throw new Error('Must target self');
      } else {
        const dx = Math.abs(c.x - a.x), dy = Math.abs(c.y - a.y);
        if (!def.abilityRange.some(([x,y]) => x === dx && y === dy)) throw new Error('Target out of range');
        if (def.abilityTarget <= 4 && !target) throw new Error('No target');
        if (def.abilityTarget === 2 && target?.playerSlot !== c.playerSlot) throw new Error('Target an ally');
        if (def.abilityTarget === 3 && target?.playerSlot === c.playerSlot) throw new Error('Target an enemy');
      }
      energy -= def.abilityCost; usedAbilities.add(c.id);
      if (c.capType === 5) moves++;
      else if (c.capType === 1 && target) damage(target, 2);
      else if (c.capType === 2 && target) target.shield += 3;
      else if (c.capType === 3 && target) target.health = Math.min(defs.get(target.capType)?.maxHealth ?? target.health, target.health + 3);
      else if (c.capType === 4 && target) damage(target, 4);
    }
    const winner = caps.find(c => !c.dead && c.x === 2 && c.y === (c.playerSlot === 0 ? 4 : 0));
    if (winner) winnerSlot = winner.playerSlot;
    if (winnerSlot !== null) continue;
    // Determine all captures before removing any pieces.
    const captured = caps.filter(c => surrounded(caps, layout, c));
    for (const c of captured) {
      c.x = null; c.y = null; c.health = defs.get(c.capType)?.maxHealth ?? c.health;
      c.shield = 0; c.stunnedTurns = 0;
      c.availableTurn = game.turnCount + (c.playerSlot === game.turnCount % 2 ? 6 : 5);
      if (c.playerSlot === hand?.playerSlot) requeue(c.id);
    }

  }
  return { caps, energy, actions, moves, usedAbilities, winnerSlot, hand: handIds(roster, caps, game.turnCount, hand?.handSize) };
}
