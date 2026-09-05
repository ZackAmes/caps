import type { CapTypeDef } from './types';

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
  if (type === 6) return `Generates ${def.passiveAmount} energy per owner turn on board`;
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

