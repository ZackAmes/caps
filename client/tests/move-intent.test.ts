import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readMoveIntent, intentTypedData, INTENT_LIFETIME_MS } from '@caps/game-core/move-intent';
import { encodeActions } from '@caps/game-core/encode';
import type { ChainGame, TurnAction } from '@caps/game-core/types';
const game: ChainGame = {id:9,turnCount:3,player1:'0x123',player2:'0x456',layout:0,setId:0,over:false,winner:'0x0',winnerSlot:2,energy:1,p1Energy:1,p2Energy:1,effectIds:[],caps:[]};
const now = 1800000000000;
const actions: TurnAction[] = [{capId:2,kind:'Play',x:2,y:4},{capId:4,kind:'Move',x:0,y:0},{capId:6,kind:'Ability',x:2,y:1},{capId:8,kind:'StackAbility',targetId:3}];
const raw = {identity:'0x0456',game_id:'0x9',turn:'0x3',world:'0x789',timestamp:String(now),tx_hash:'0xabc',status:1,actions:encodeActions(actions).map(String)};
test('shared move payload round trips every action variant, a pass, and cancellation', () => {
  const parsed = readMoveIntent(raw, '0x0789', game, now)!;
  assert.deepEqual(parsed.actions, actions);
  assert.deepEqual(intentTypedData(parsed).message.actions, raw.actions);
  assert.equal(typeof intentTypedData(parsed).message.status, 'number');
  assert.deepEqual(readMoveIntent({...raw,actions:['0']}, '0x789', game, now)?.actions, []);
  assert.equal(readMoveIntent({...raw,status:2}, '0x789', game, now)?.status, 2);
});
test('previews reject wrong player, world, turn, game, expiry, future and relay claims of confirmation', () => {
  for (const change of [{identity:'0x123'},{world:'0x987'},{turn:2},{game_id:10},{timestamp:now-INTENT_LIFETIME_MS-1},{timestamp:now+5001},{status:3}]) {
    assert.equal(readMoveIntent({...raw,...change}, '0x789', game, now), null);
  }
  assert.equal(readMoveIntent(raw, '0x789', {...game,over:true}, now), null);
});
test('malformed action arrays never become previews', () => {
  for (const actions of [[],[0,1],[1,2,0,2],[1,2,1,15,0],[1,2,3,0],[1,2,4,0,0],[33],['bad'],[1,Number.MAX_SAFE_INTEGER+1,0,0,0]]) {
    assert.equal(readMoveIntent({...raw,actions}, '0x789', game, now), null);
  }
});
