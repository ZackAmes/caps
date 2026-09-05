import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { handIds, previewTurn } from '../src/lib/dojo/preview';
import type { ChainCap, ChainGame, ChainHand, CapTypeDef, LayoutConfig } from '../src/lib/dojo/client';
const layout: LayoutConfig = { id: 0, name: 'Perimeter', description: 'Test perimeter', width: 5, height: 5, p1Deploy: [2,0], p2Deploy: [2,4], isWalkable: (x,y) => x>=0 && y>=0 && x<5 && y<5 && (x===0 || x===4 || y===0 || y===4) };
const piece = (id: number, playerSlot=0, capType=1, x:number|null=null, y:number|null=null): ChainCap => ({id, owner:'0x123', playerSlot, capType, setId:0, x,y,health:6,shield:0,stunnedTurns:0,availableTurn:0,dead:false});
const definition = (id:number):CapTypeDef => ({id,name:'Piece',description:'',maxHealth:6,attack:2,moveRange:1,attackRange:1,playCost:0,moveCost:0,abilityCost:2,abilityDescription:'',abilityTarget:id===5?1:3,abilityRange:[[1,0],[0,1],[1,1]],passiveType:0,passiveAmount:0,passiveCondition:0,passiveRadius:0,passiveEffectType:0});
const defs = new Map([0,1,2,3,4,5].map(i=>[i,definition(i)]));
const game = (caps:ChainCap[], turnCount=0):ChainGame => ({id:1,player1:'0x123',player2:'0x123',layout:0,setId:0,turnCount,over:false,winner:'0x0',winnerSlot:2,energy:3,p1Energy:3,p2Energy:1,effectIds:[],caps});
const hand:ChainHand = {gameId:1,playerSlot:0,roster:[1,3,5,7,9,11],handSize:4,window:[1,3,5,7]};
describe('new turn rules preview',()=>{
 test('draw queue skips unavailable pieces',()=>{
  const caps=[piece(1),piece(3),piece(5),piece(7),piece(9),piece(11)];
  caps[0].dead=true;caps[1].x=0;caps[1].y=0;caps[2].availableTurn=5;
  assert.deepEqual(handIds(hand.roster,caps,3), [7,9,11]);
  assert.deepEqual(handIds(hand.roster,caps,5), [5,7,9,11]);
 });
 test('chosen deployment refills without dropping other hand members',()=>{
  const state=game([1,3,5,7,9,11].map(id=>piece(id)));
  const p=previewTurn(state,hand,defs,layout,[{capId:5,kind:'Play',x:2,y:0}]);
  assert.deepEqual(p.hand, [1,3,7,9]);assert.equal(p.energy, 3);assert.equal(p.actions, 0);
 });
 test('normal movement limited, ability grants extra move',()=>{
  const state=game([piece(11,0,5,0,0)]);
  assert.throws(()=>previewTurn(state,hand,defs,layout,[{capId:11,kind:'Move',x:1,y:0},{capId:11,kind:'Move',x:2,y:0}]), /No\ normal\ actions/);
  const p=previewTurn(state,hand,defs,layout,[{capId:11,kind:'Move',x:1,y:0},{capId:11,kind:'Ability',x:1,y:0},{capId:11,kind:'Move',x:2,y:0}]);
  assert.equal(p.caps[0].x, 2);assert.equal(p.energy, 1);assert.equal(p.moves, 0);
 });
 test('automatic surround returns opponent to cooldown bench',()=>{
  const p=previewTurn(game([piece(4,1,1,0,0),piece(3,0,1,1,0),piece(5,0,2,0,2)]),hand,defs,layout,[{capId:5,kind:'Move',x:0,y:1}]);
  assert.equal(p.caps[0].x, null);assert.equal(p.caps[0].availableTurn, 5);assert.equal(p.caps[0].dead, false);
 });
 test('both sides have correct goals despite shared wallet',()=>{
  assert.equal(previewTurn(game([piece(3,0,1,1,4)]),hand,defs,layout,[{capId:3,kind:'Move',x:2,y:4}]).winnerSlot, 0);
  assert.equal(previewTurn(game([piece(4,1,1,3,0)],1),null,defs,layout,[{capId:4,kind:'Move',x:2,y:0}]).winnerSlot, 1);
 });
 test('ability uses symmetric range and shield-aware combat persists',()=>{
  const enemy=piece(6,1,2,4,0);enemy.health=10;enemy.shield=1;
  const p=previewTurn(game([piece(3,0,1,4,1),enemy]),hand,defs,layout,[{capId:3,kind:'Ability',x:4,y:0},{capId:3,kind:'Move',x:4,y:0}]);
  assert.equal(p.caps[1].health, 7);assert.equal(p.caps[1].shield, 0);assert.equal(p.caps[0].y, 1);
 });
 test('cannot use enemy piece or repeat ability',()=>{
  assert.throws(()=>previewTurn(game([piece(4,1,5,0,0)]),hand,defs,layout,[{capId:4,kind:'Move',x:1,y:0}]), /unavailable/);
  assert.throws(()=>previewTurn(game([piece(11,0,5,0,0)]),hand,defs,layout,[{capId:11,kind:'Ability',x:0,y:0},{capId:11,kind:'Ability',x:0,y:0}]), /once\ per\ turn/);
 });
 test('pass is valid and does not mutate input',()=>{
  const state=game([piece(1)]);const p=previewTurn(state,hand,defs,layout,[]);
  p.caps[0].health=1;assert.equal(state.caps[0].health, 6);assert.equal(p.actions, 1);
 });
});
