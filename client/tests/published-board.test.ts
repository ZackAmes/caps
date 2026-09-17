import {test} from 'node:test';
import assert from 'node:assert/strict';
import {encodeBoard,decodeBoard,validateBoard,type BoardDraft} from '@caps/game-core/published-board';
import {pathDistance} from '@caps/game-core/board';
import {boardArt} from '../src/lib/game/board-art';
test('published board ABI preserves arbitrary art and uses graph distance',()=>{
 const draft:BoardDraft={name:'自由 board',width:15,height:15,viewWidth:8,viewHeight:10,p1Goal:[0,0],p2Goal:[14,14],spots:[{at:[0,0],position:[-2,-3]},{at:[14,14],position:[1,4],energy:true}],connections:[{from:[0,0],to:[14,14],via:[[2,0]]}]};
 const board=decodeBoard(['0','7','0x123',...encodeBoard(draft).map(String)])!;
 assert.equal(board.definition.name,draft.name);
 assert.deepEqual(board.definition.spots,draft.spots.map(s=>({...s,energy:s.energy??false})));
 assert.equal(pathDistance(board.layout,[0,0],[14,14]),1);
 assert.deepEqual(boardArt(board.layout).segments,[{from:[-2,-3],to:[2,0]},{from:[2,0],to:[1,4]}]);
 assert.throws(()=>validateBoard({...draft,connections:[]}),/connected/);
});
