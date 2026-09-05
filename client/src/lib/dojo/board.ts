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

function defineLayout(layout: LayoutConfig): LayoutConfig {
  const matchesTrack = layout.isWalkable;
  return {
    ...layout,
    isWalkable: (x, y) => Number.isInteger(x) && Number.isInteger(y)
      && x >= 0 && y >= 0 && x < layout.width && y < layout.height
      && matchesTrack(x, y),
  };
}

export const LAYOUTS: Record<number, LayoutConfig> = {
  [LAYOUT_PERIMETER_5X5]: defineLayout({
    id: LAYOUT_PERIMETER_5X5,
    name: "5x5 Perimeter Track",
    description: "Outer boundary track only",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) => x === 0 || x === 4 || y === 0 || y === 4,
  }),
  [LAYOUT_CROSS_5X5]: defineLayout({
    id: LAYOUT_CROSS_5X5,
    name: "5x5 Track + Cross",
    description: "Perimeter plus center cross lanes",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) =>
      x === 0 || x === 4 || y === 0 || y === 4 || x === 2 || y === 2,
  }),
  [LAYOUT_DIAGONAL_X_5X5]: defineLayout({
    id: LAYOUT_DIAGONAL_X_5X5,
    name: "5x5 Diagonal X Track",
    description: "Perimeter with diagonal corner-to-corner routes through center",
    width: 5,
    height: 5,
    p1Deploy: [2, 0],
    p2Deploy: [2, 4],
    isWalkable: (x: number, y: number) =>
      x === 0 || x === 4 || y === 0 || y === 4 || x === y || x + y === 4,
  }),
  [LAYOUT_DIAMOND_5X5]: defineLayout({
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
  }),
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

