import { LAYOUT_DUEL_RING, type LayoutConfig, type Position } from '@caps/game-core/board';
import type { CapTypeDef, PieceSnapshot, StackEntry, TurnAction } from '@caps/game-core/types';
import { artPosition, boardArt, orient } from './board-art';
import { impactFootprint, pieceSymbol } from './presentation';
import { square } from './history';

/** Shortest logical path, expanded into the exact bends drawn by the board artist. */
export function movementRoute(layout: LayoutConfig, from: Position, to: Position, viewer: number | null): Position[] {
    const art = boardArt(layout), start = from.join(','), end = to.join(',');
    const paths = new Map<string, Position[]>([[start, [from]]]);
    for (const [key, path] of paths) {
        if (key === end) break;
        for (const next of layout.neighbors(path[path.length - 1])) {
            if (!paths.has(next.join(','))) paths.set(next.join(','), [...path, next]);
        }
    }
    const path = paths.get(end);
    if (!path) return [artPosition(art, ...from, viewer), artPosition(art, ...to, viewer)];
    const points: Position[] = [artPosition(art, ...from, viewer)];
    for (let i = 1; i < path.length; i++) {
        const a = path[i - 1], b = path[i];
        const route = (layout.artwork?.routes ?? (layout.id === LAYOUT_DUEL_RING ? [] : layout.connections ?? []))
            .find(r => (r.from.join(',') === a.join(',') && r.to.join(',') === b.join(',')) ||
                (r.to.join(',') === a.join(',') && r.from.join(',') === b.join(',')));
        if (route) {
            const bends = route.from.join(',') === a.join(',') ? route.via : [...route.via].reverse();
            for (const bend of bends) points.push(layout.artwork ? orient(bend, viewer) : orient([bend[0] - (layout.width - 1) / 2, bend[1] - (layout.height - 1) / 2], viewer));
        }
        points.push(artPosition(art, ...b, viewer));
    }
    return points;
}

/** Constant speed across unequal segments; easing is applied by the caller. */
export function pointAlong(points: Position[], progress: number): Position {
    const lengths = points.slice(1).map((p, i) => Math.hypot(p[0] - points[i][0], p[1] - points[i][1]));
    let remaining = lengths.reduce((a, b) => a + b, 0) * Math.max(0, Math.min(1, progress));
    for (let i = 0; i < lengths.length; i++) {
        if (remaining <= lengths[i] && lengths[i] > 0) {
            const t = remaining / lengths[i];
            return [points[i][0] + (points[i + 1][0] - points[i][0]) * t, points[i][1] + (points[i + 1][1] - points[i][1]) * t];
        }
        remaining -= lengths[i];
    }
    return points[points.length - 1];
}

export interface BoardCue {
    id: string;
    kind: 'move' | 'deploy' | 'ability' | 'negate' | 'resolve' | 'attack';
    from: Position | null;
    cells: Position[];
    color: string;
}
const location = (piece?: PieceSnapshot): Position | null => piece && piece.x !== null && piece.y !== null ? [piece.x, piece.y] : null;
export function actionCues(game: number, turn: number, actions: TurnAction[], before: PieceSnapshot[], stack: StackEntry[]): BoardCue[] {
    const positions = new Map(before.map(p => [p.id, location(p)]));
    return actions.map((action, i) => {
        const from = positions.get(action.capId) ?? null;
        const target = action.kind === 'StackAbility' ? location(before.find(p => p.id === stack.find(e => e.id === action.targetId)?.sourceId)) : [action.x, action.y] as Position;
        const occupied = target && [...positions].some(([id, pos]) => id !== action.capId && pos?.join(',') === target.join(','));
        const kind = action.kind === 'Play' ? 'deploy' : action.kind === 'StackAbility' ? 'negate' : action.kind === 'Ability' ? 'ability' : occupied ? 'attack' : 'move';
        if ((kind === 'move' || kind === 'deploy') && target) positions.set(action.capId, target);
        const data = action.kind === 'StackAbility' ? [action.capId, action.kind, action.targetId] : [action.capId, action.kind, action.x, action.y];
        return {id:`${game}:${turn}:action:${i}:${data.join(':')}`,kind,from,cells:target ? [target] : from ? [from] : [],
            color:kind === 'negate' ? '#fbbf24' : kind === 'ability' ? '#c4b5fd' : kind === 'attack' ? '#fb7185' : '#67e8f9'};
    });
}
export function resolvedCue(game: number, turn: number, entry: StackEntry, pieces: PieceSnapshot[], layout: LayoutConfig): BoardCue {
    return {id:`${game}:${turn}:resolve:${entry.id}`,kind:'resolve',from:location(pieces.find(p => p.id === entry.sourceId)),
        cells:[...impactFootprint(entry, pieces, layout)].map(key => key.split(',').map(Number) as Position),
        color:entry.impact.kind === 'Damage' ? '#fb7185' : entry.impact.kind === 'Heal' ? '#6ee7b7' : '#93c5fd'};
}
/** One visual trigger for planning, relay broadcast, and confirmation of the same action. */
export class CueLedger {
    private seen = new Set<string>();
    fresh(cues: BoardCue[]) {
        return cues.filter(cue => {
            if (this.seen.has(cue.id)) return false;
            if (this.seen.size >= 512) this.seen.delete(this.seen.values().next().value!);
            this.seen.add(cue.id); return true;
        });
    }
}
export function moveDigest(actions: TurnAction[], pieces: PieceSnapshot[], defs: Map<number, CapTypeDef>) {
    const action = actions[0];
    if (!action) return {icon:'↷',title:'Passed',detail:'No action taken',extra:0};
    const piece = pieces.find(p => p.id === action.capId), name = piece ? defs.get(piece.capType)?.name ?? 'Piece' : 'Piece';
    const from = location(piece);
    const detail = action.kind === 'StackAbility' ? `Negate effect #${action.targetId}` : action.kind === 'Ability' ? `Ability → ${square(action.x, action.y)}` :
        action.kind === 'Play' ? `Deployed → ${square(action.x, action.y)}` :
        pieces.some(p => !p.dead && p.id !== action.capId && p.x === action.x && p.y === action.y) ? `Attack → ${square(action.x, action.y)}` : `${from ? square(...from) : 'Move'} → ${square(action.x, action.y)}`;
    return {icon:piece ? pieceSymbol(piece.capType) : '●',title:name,detail,extra:actions.length - 1};
}

export interface TurnNotice {
    gameId: number; turn: number; playerSlot: number; actions: TurnAction[]; before: PieceSnapshot[];
    phase: 'pending' | 'confirmed' | 'cancelled' | 'expired';
}
