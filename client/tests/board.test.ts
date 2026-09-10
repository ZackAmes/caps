import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LAYOUTS, isValidStep } from '@caps/game-core/board';

test('every track rejects off-board and fractional coordinates', () => {
  for (const layout of Object.values(LAYOUTS)) {
    for (const [x, y] of [[-1, 0], [0, -1], [layout.width, 0], [0, layout.height], [1.5, 0]]) {
      assert.equal(layout.isWalkable(x, y), false);
    }
    assert.equal(isValidStep(layout.id, [0, 0], [-1, 0]), false);
    assert.equal(isValidStep(layout.id, [layout.width - 1, layout.height - 1], [layout.width, layout.height - 1]), false);
  }
});

test('all layouts retain bases, objectives, and explicit valid moves', () => {
  for (const layout of Object.values(LAYOUTS)) {
    for (const [x, y] of [layout.p1Deploy, layout.p2Deploy, ...(layout.energySpaces ?? [])]) {
      assert.equal(layout.isWalkable(x, y), true);
    }
    for (const next of layout.neighbors(layout.p1Deploy)) assert.equal(isValidStep(layout.id, layout.p1Deploy, next), true);
    assert.equal(isValidStep(layout.id, [0, 0], [0, 0]), false);
    assert.equal(isValidStep(layout.id, [0, 0], [2, 0]), false);
  }
});

test('Duel grid has the exact outer counts, inner grid, and rotational symmetry', () => {
  const layout = LAYOUTS[5];
  const points = [];
  for (let y = 0; y < 5; y++) for (let x = 0; x < 7; x++) if (layout.isWalkable(x,y)) points.push([x,y]);
  assert.equal(points.length, 29);
  for (const y of [0,4]) assert.equal(points.filter(p => p[1] === y).length, 7);
  for (const x of [0,6]) assert.equal(points.filter(p => p[0] === x).length, 5);
  assert.equal(points.filter(([x,y]) => x > 0 && x < 6 && y > 0 && y < 4).length, 9);
  for (const [x,y] of points) {
    assert.equal(layout.isWalkable(6-x,4-y), true);
    for (const [nx,ny] of layout.neighbors([x,y])) assert.equal(isValidStep(5,[6-x,4-y],[6-nx,4-ny]),true);
  }
  for (const [a,b] of [ [[0,0],[1,1]], [[6,0],[5,1]], [[0,4],[1,3]], [[6,4],[5,3]], [[2,0],[3,1]], [[4,4],[3,3]], [[1,2],[3,2]] ]) {
    assert.equal(isValidStep(5,a as [number,number],b as [number,number]),true);
  }
  assert.equal(isValidStep(5,[3,0],[3,1]),false);
  assert.equal(isValidStep(5,[3,4],[3,3]),false);
  assert.equal(isValidStep(5,[4,0],[3,1]),false);
  assert.equal(isValidStep(5,[1,1],[3,2]),false);
});

test('packed contract tables agree with client graph distances for every source and destination', async () => {
  const { readFileSync } = await import('node:fs');
  const { pathDistance } = await import('@caps/game-core/board');
  const source = readFileSync(new URL('../../contracts/src/logic/board_data.cairo', import.meta.url),'utf8');
  const rows = new Map<string,bigint[]>();
  for (const match of source.matchAll(/\((\d+),\s*(\d+)\)\s*=>\s*array!\[([^\]]+)\]/g)) {
    rows.set(`${match[1]}:${match[2]}`,match[3].split(',').map(s=>s.trim()).filter(Boolean).map(BigInt));
  }
  for (const layout of Object.values(LAYOUTS)) {
    const size = layout.width * layout.height;
    for (let a=0;a<size;a++) for(let b=0;b<size;b++) {
      const block = rows.get(`${layout.id}:${a}`)?.[Math.floor(b/16)] ?? ((1n << 128n)-1n);
      const actual = Number((block >> BigInt(8*(b%16))) & 255n);
      const distance = pathDistance(layout,[a%layout.width,Math.floor(a/layout.width)],[b%layout.width,Math.floor(b/layout.width)]);
      assert.equal(actual,Number.isFinite(distance) ? distance : 255,`layout ${layout.id}, ${a} -> ${b}`);
    }
  }
});
