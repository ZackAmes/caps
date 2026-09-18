import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeClock, clockRemaining, clockLabel } from '@caps/game-core/clock';

const clock = decodeClock(['1', '1', '100', '123', '1000', '2', '1030']);
test('clock decoding preserves independent banks and chain time', () => {
    assert.deepEqual(clockRemaining(clock, 2, false), [70, 123]);
    assert.deepEqual(clockRemaining(clock, 3, false), [100, 93]);
    assert.ok(Math.abs(clockRemaining(clock, 2, false, 1099.8)![0] - 0.2) < 0.001);
    assert.deepEqual(clockRemaining(clock, 2, false, 1100), [0, 123]);
    assert.deepEqual(clockRemaining(clock, 2, false, 999), [100, 123]);
});
test('finished clocks freeze and legacy clocks stay unset', () => {
    assert.deepEqual(clockRemaining(clock, 2, true, 9999), [100, 123]);
    assert.equal(clockRemaining({...clock, enabled: false}, 2, false), null);
    assert.equal(clockLabel(null), '—');
    assert.equal(clockLabel(120), '2:00');
    assert.equal(clockLabel(0.2), '0:01');
    assert.equal(clockLabel(-1), '0:00');
});
test('clock responses reject malformed values', () => {
    for (const values of [[], ['1','1','120','120','1000','2'], ['1','2','120','120','1000','2','1000'], ['1','1','-1','120','1000','2','1000'], ['1','1','120','120','1000','3','1000']]) {
        assert.throws(() => decodeClock(values));
    }
});

test('waiting freezes both displayed banks, survives refreshes, and clears on resume or a new turn', async () => {
    const {holdClock} = await import('../src/lib/game/clock');
    const held = holdClock(null,clock,2,false,1030,true)!;
    assert.deepEqual(held.seconds,[70,123]);
    assert.equal(holdClock(held,{...clock,chainTime:1040},2,false,1040,true),held);
    assert.equal(holdClock(held,clock,2,false,1040,false),null);
    assert.deepEqual(holdClock(held,{...clock,p1Seconds:80,runningSince:1040},3,false,1040,true)?.seconds,[80,123]);
    assert.equal(holdClock(held,clock,2,true,1040,true),null);
    assert.equal(holdClock(held,{...clock,gameId:2},2,false,1040,true)?.gameId,2);
});
