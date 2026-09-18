import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeBoard, encodeBoard, type BoardDraft } from '@caps/game-core/published-board';
import { actionCues, CueLedger, movementRoute, pointAlong, moveDigest } from '../src/lib/game/motion';
import type { PieceSnapshot, TurnAction } from '@caps/game-core/types';

test('movement follows published artwork bends in either direction and either orientation', () => {
    const draft: BoardDraft = {name:'Bends',width:15,height:15,viewWidth:8,viewHeight:10,p1Goal:[0,0],p2Goal:[14,14],
        spots:[{at:[0,0],position:[-2,-3]},{at:[7,7],position:[0,1]},{at:[14,14],position:[1,4]}],
        connections:[{from:[0,0],to:[7,7],via:[[2,0]]},{from:[7,7],to:[14,14]}]};
    const layout = decodeBoard(['0','7','0x123',...encodeBoard(draft).map(String)])!.layout;
    const path = movementRoute(layout,[0,0],[14,14],1);
    assert.deepEqual(path,[[-2,-3],[2,0],[0,1],[1,4]]);
    assert.deepEqual(movementRoute(layout,[14,14],[0,0],1),[...path].reverse());
    assert.deepEqual(movementRoute(layout,[0,0],[14,14],0),path.map(([x,y]) => [-x,-y]));
    assert.deepEqual(pointAlong([[0,0],[1,0],[1,3]],0.5),[1,1]);
    assert.deepEqual(pointAlong(path,1),[1,4]);
});
const before: PieceSnapshot[] = [{id:1,playerSlot:1,capType:1,x:0,y:0,health:6,shield:0,stunnedTurns:0,availableTurn:0,dead:false}];
test('planning, relay updates and confirmation share one cue; another turn or action gets its own', () => {
    const ledger = new CueLedger(), actions: TurnAction[] = [{capId:1,kind:'Move',x:1,y:0},{capId:1,kind:'Ability',x:2,y:0}];
    const cues = actionCues(1,3,actions,before,[]);
    assert.deepEqual(cues[1].from,[1,0]);
    assert.equal(ledger.fresh(cues).length,2);
    assert.equal(ledger.fresh(actionCues(1,3,structuredClone(actions),before,[])).length,0);
    assert.equal(ledger.fresh(actionCues(1,4,actions,before,[])).length,2);
    assert.equal(ledger.fresh(actionCues(2,3,actions,before,[])).length,2);
});
test('opponent digest covers pass, deployment, moves, abilities and stack targets without requiring a roster name', () => {
    assert.equal(moveDigest([],before,new Map()).title,'Passed');
    assert.equal(moveDigest([{capId:1,kind:'Play',x:2,y:0}],before,new Map()).detail,'Deployed → C1');
    assert.equal(moveDigest([{capId:1,kind:'Move',x:1,y:0}],before,new Map()).detail,'A1 → B1');
    assert.equal(moveDigest([{capId:1,kind:'Move',x:1,y:0}],[...before,{...before[0],id:2,playerSlot:0,x:1}],new Map()).detail,'Attack → B1');
    assert.equal(moveDigest([{capId:1,kind:'Ability',x:2,y:1}],before,new Map()).detail,'Ability → C2');
    assert.equal(moveDigest([{capId:1,kind:'StackAbility',targetId:8}],before,new Map()).detail,'Negate effect #8');
});
