import { resolveReadyStack, resolveImpact, canTargetPending } from '@caps/game-core/stack';
import { isEnergySpace, pathDistances, pathDistance } from '@caps/game-core/board';
import { passiveBonus } from '@caps/game-core/passives';
import { previewTurn } from '@caps/game-core/preview';
import type { ChainCap, TurnAction } from '@caps/game-core/types';
import type { PositionV7 } from '../game/v7';
import type { Strategy } from '../ports';

type Preview = ReturnType<typeof previewTurn>;

/** Small deterministic beam search. No RPC, signing, account keys, or worker state. */
export const greedyStrategy: Strategy<PositionV7, TurnAction> = {
  name: 'greedy-v1',
  chooseTurn(position) {
    const simulate = (queue: TurnAction[]) => previewTurn(position.game, position.hand, position.definitions, position.layout, queue, position.stack);
    const slot = position.game.turnCount % 2;
    const distances = goalDistances(position, slot);
    let best = { queue: [] as TurnAction[], state: simulate([]), score: -Infinity };
    best.score = score(position, best.state, slot, distances);
    let beam = [best];
    for (let depth = 0; depth < 3; depth++) {
      const next: typeof beam = [];
      for (const node of beam) {
        if (node.state.winnerSlot !== null) continue;
        for (const action of candidates(position, node.state, slot)) {
          const queue = [...node.queue, action];
          try {
            const state = simulate(queue);
            const value = score(position, state, slot, distances) - queue.length * 0.01;
            const option = { queue, state, score: value };
            next.push(option);
            if (value > best.score) best = option;
          } catch { /* The rules module filters unaffordable/illegal candidate sequences. */ }
        }
      }
      beam = next.sort((a, b) => b.score - a.score).slice(0, 8);
      if (!beam.length || best.state.winnerSlot === slot) break;
    }
    return best.queue;
  },
};

function candidates(p: PositionV7, state: Preview, slot: number): TurnAction[] {
  const actions: TurnAction[] = [];
  const deploy = slot === 0 ? p.layout.p1Deploy : p.layout.p2Deploy;
  if (state.actions > 0) for (const id of state.hand) actions.push({ capId: id, kind: 'Play', x: deploy[0], y: deploy[1] });
  for (const cap of state.caps) {
    if (cap.playerSlot !== slot || cap.dead || cap.x === null || cap.y === null || cap.stunnedTurns) continue;
    if (state.actions + state.moves > 0) {
      for (const [x, y] of p.layout.neighbors([cap.x, cap.y])) actions.push({ capId: cap.id, kind: 'Move', x, y });
    }
    const def = p.definitions.get(cap.capType);
    if (!def?.abilityTarget || state.usedAbilities.has(cap.id) || def.abilityCost > state.energy) continue;
    if (def.abilityTarget >= 6) {
      for (const entry of state.stack.entries) if (canTargetPending(def.abilityTarget, slot, entry)) actions.push({capId:cap.id,kind:'StackAbility',targetId:entry.id});
    } else if (def.abilityTarget === 1) actions.push({ capId: cap.id, kind: 'Ability', x: cap.x, y: cap.y });
    else for (let x = 0; x < p.layout.width; x++) for (let y = 0; y < p.layout.height; y++) {
      if (p.layout.isWalkable(x, y)) actions.push({ capId: cap.id, kind: 'Ability', x, y });
    }
  }
  return actions;
}

function goalDistances(p: PositionV7, slot: number): Map<string, number> {
  const goal = slot === 0 ? p.layout.p2Deploy : p.layout.p1Deploy;
  return pathDistances(p.layout, goal);
}

function score(p: PositionV7, state: Preview, slot: number, distances: Map<string, number>): number {
  if (state.winnerSlot !== null) return state.winnerSlot === slot ? 1_000_000 : -1_000_000;
  // Response moves are scored after effects due at this turn boundary.
  const before = state;
  state = { ...state, caps: resolveReadyStack(state.stack, state.caps, p.definitions, p.layout, p.game.turnCount + 1).caps };
  let value = state.energy * 0.5;
  // Small, deliberately optimistic estimate for newly announced delayed effects.
  for (const entry of before.stack.entries.filter(e => e.id > p.stack.nextId)) {
    const forecast = resolveImpact(entry, before.caps, p.definitions, p.layout);
    for (let i = 0; i < forecast.length; i++) value += (forecast[i].health - before.caps[i].health) * (forecast[i].playerSlot === slot ? 1 : -1) * 0.75;
  }
  let closest = 20;
  const ownGoal = slot === 0 ? p.layout.p1Deploy : p.layout.p2Deploy;
  const goalDefended = state.caps.some(c => c.playerSlot === slot && c.x === ownGoal[0] && c.y === ownGoal[1]);
  for (const cap of state.caps) {
    if (cap.dead) continue;
    const sign = cap.playerSlot === slot ? 1 : -1;
    value += sign * (cap.health + cap.shield) * 0.5;
    if (!onBoard(cap)) continue;
    value += sign * 6;
    if (cap.playerSlot === slot) {
      const distance = distances.get(`${cap.x},${cap.y}`) ?? 20;
      closest = Math.min(closest, distance);
      value += (8 - distance) * 3;
      if (isEnergySpace(p.layout, cap.x!, cap.y!)) value += 5;
      value += 2 * passiveBonus('EnergyGeneration', cap, state.caps, p.definitions, p.layout);
    } else if (!goalDefended && pathDistance(p.layout, [cap.x!, cap.y!], ownGoal) <= 1) {
      value -= 1000;
    }
  }
  if (closest < 20) value += (8 - closest) * 12;
  return value;
}

function onBoard(cap: ChainCap) { return !cap.dead && cap.x !== null && cap.y !== null; }
