import boards from '../../../rules/boards.json';
export const LAYOUT_PERIMETER_5X5 = 0;
export const LAYOUT_CROSS_5X5 = 1;
export const LAYOUT_DIAGONAL_X_5X5 = 2;
export const LAYOUT_DIAMOND_5X5 = 3;
export const LAYOUT_DUEL_7X9 = 4;
export const LAYOUT_DUEL_7X5 = 5;
export type Position = [number, number];
export interface LayoutConfig {
  id: number; name: string; description: string;
  width: number; height: number;
  p1Deploy: Position; p2Deploy: Position;
  energySpaces?: Position[];
  isWalkable(x: number, y: number): boolean;
  neighbors(position: Position): Position[];
}

/** Coordinates locate tiles for rendering. Only consecutive path entries create edges. */
export function createLayout(config: Omit<LayoutConfig, 'isWalkable' | 'neighbors'>, paths: Position[][]): LayoutConfig {
  const graph = new Map<string, Map<string, Position>>();
  for (const path of paths) {
    for (const p of path) {
      if (!p.every(Number.isInteger) || p[0] < 0 || p[0] >= config.width || p[1] < 0 || p[1] >= config.height) throw new Error('Invalid path tile');
      if (!graph.has(p.join(','))) graph.set(p.join(','), new Map());
    }
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1], b = path[i];
      if (a.join(',') === b.join(',')) throw new Error('Path cannot connect a tile to itself');
      graph.get(a.join(','))!.set(b.join(','), [...b]);
      graph.get(b.join(','))!.set(a.join(','), [...a]);
    }
  }
  return { ...config,
    isWalkable: (x, y) => graph.has(`${x},${y}`),
    neighbors: p => [...(graph.get(p.join(','))?.values() ?? [])].map(n => [...n]),
  };
}
const pathsFor = (id: number): Position[][] => {
  const board = boards.find(b => b.id === id);
  if (!board) throw new Error(`Unknown layout ${id}`);
  return [...(board.extends !== undefined ? pathsFor(board.extends) : []), ...board.paths as Position[][]];
};
export const LAYOUTS: Record<number, LayoutConfig> = Object.fromEntries(boards.map(b => [b.id, createLayout({ id: b.id, name: b.name, description: b.description, width: b.width, height: b.height, p1Deploy: b.p1Deploy as Position, p2Deploy: b.p2Deploy as Position, energySpaces: b.energySpaces as Position[] }, pathsFor(b.id))]));
export function getLayout(id: number): LayoutConfig {
  const layout = LAYOUTS[id];
  if (!layout) throw new Error(`Unknown layout ${id}`);
  return layout;
}
export function pathDistances(layout: LayoutConfig, from: Position): Map<string, number> {
  if (!layout.isWalkable(...from)) return new Map();
  const distances = new Map([[from.join(','), 0]]);
  const queue = [from];
  for (let i = 0; i < queue.length; i++) {
    const p = queue[i];
    for (const next of layout.neighbors(p)) if (!distances.has(next.join(','))) {
      distances.set(next.join(','), distances.get(p.join(','))! + 1);
      queue.push(next);
    }
  }
  return distances;
}
export function pathDistance(layout: LayoutConfig, from: Position, to: Position): number {
  return pathDistances(layout, from).get(to.join(',')) ?? Infinity;
}
export function isValidStep(layoutId: number, from: Position, to: Position): boolean {
  return getLayout(layoutId).neighbors(from).some(n => n[0] === to[0] && n[1] === to[1]);
}

export function goalSlot(layout: LayoutConfig, x: number, y: number): number | null {
  return layout.p1Deploy[0] === x && layout.p1Deploy[1] === y ? 0 : layout.p2Deploy[0] === x && layout.p2Deploy[1] === y ? 1 : null;
}
export function isEnergySpace(layout: LayoutConfig, x: number, y: number): boolean {
  return (layout.energySpaces ?? []).some(p => p[0] === x && p[1] === y);
}
