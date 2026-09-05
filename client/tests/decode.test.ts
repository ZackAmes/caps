import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeCapType, decodeGame, decodeHand } from '../src/lib/dojo/decode';
const felt = (n: number | string) => String(n);
function text(value:string):string[] {
 const bytes = new TextEncoder().encode(value);
 const words:string[]=[];
 const word=(b:Uint8Array)=>'0x'+Array.from(b,x=>x.toString(16).padStart(2,'0')).join('');
 let i=0;for(;i+31<=bytes.length;i+=31) words.push(word(bytes.slice(i,i+31)));
 return [String(words.length),...words,i<bytes.length?word(bytes.slice(i)):'0',String(bytes.length-i)];
}
test('piece text parses full words, pending bytes, and UTF-8',()=>{
 const description='This description spans more than thirty-one bytes.';
 const data=['0','0',...text('Generator'),...text(description),'5','1','1','1','0','0','0',...text('Energy ⚡'),'0','0','6','1'];
 const def=decodeCapType(data)!;
 assert.equal(def.name, 'Generator');assert.equal(def.description, description);assert.equal(def.abilityDescription, 'Energy ⚡');assert.equal(def.passiveAmount, 1);assert.equal(def.passiveType, 6);
});
test('game parses side, cooldown, death, and independent energy fields',()=>{
 const data=[0,1,'0x123','0x123',0,0,5,0,0,2,2,3,4,0,4,2,4,7,12345,2,
  3,'0x123',0,1,0,1,4,2,6,1,0,0,
  4,'0x123',1,1,0,0,6,0,0,5].map(felt);
 const game=decodeGame(data)!;assert.equal(game.winnerSlot, 2);assert.equal(game.energy, 4);assert.equal(game.p1Energy, 2);assert.equal(game.p2Energy, 4);
 assert.equal(game.caps[0].playerSlot, 0);assert.equal(game.caps[0].x, 4);assert.equal(game.caps[0].y, 2);assert.equal(game.caps[0].shield, 1);assert.equal(game.caps[0].dead, false);
 assert.equal(game.caps[1].playerSlot, 1);assert.equal(game.caps[1].x, null);assert.equal(game.caps[1].availableTurn, 5);assert.equal(game.caps[1].dead, false);
});
test('hand has queue and available window with no old cursor',()=>{
 assert.deepEqual(decodeHand([0,1,0,3,7,9,11,4,2,9,11].map(felt)), {gameId:1,playerSlot:0,roster:[7,9,11],handSize:4,window:[9,11]});
 assert.equal(decodeHand(['1']), null);
});
