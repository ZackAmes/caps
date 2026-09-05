import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LAYOUTS, isValidStep } from '../src/lib/dojo/board';

test('every track rejects off-board and fractional coordinates', () => {
  for (const layout of Object.values(LAYOUTS)) {
    for (const [x, y] of [[-1, 0], [0, -1], [5, 0], [0, 5], [1.5, 0]]) {
      assert.equal(layout.isWalkable(x, y), false);
    }
    assert.equal(isValidStep(layout.id, [0, 0], [-1, 0]), false);
    assert.equal(isValidStep(layout.id, [4, 4], [5, 4]), false);
  }
});

test('all layouts retain bases, objectives, and valid perimeter moves', () => {
  for (const layout of Object.values(LAYOUTS)) {
    for (const [x, y] of [[2, 0], [2, 4], [0, 2], [4, 2]]) {
      assert.equal(layout.isWalkable(x, y), true);
    }
    assert.equal(isValidStep(layout.id, [0, 0], [1, 0]), true);
    assert.equal(isValidStep(layout.id, [0, 0], [0, 0]), false);
    assert.equal(isValidStep(layout.id, [0, 0], [2, 0]), false);
  }
});
