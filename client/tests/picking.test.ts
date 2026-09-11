import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PerspectiveCamera, Vector3 } from 'three';
import { LAYOUTS } from '@caps/game-core/board';
import { boardArt, artPosition } from '../src/lib/game/board-art';
import { pickBoardCell } from '../src/lib/game/picking';

test('3D drops map to every canonical tile from either player view at mobile and desktop sizes', () => {
 const camera = new PerspectiveCamera(43,1,0.1,1000);
 camera.position.set(0,7.8,5.5); camera.lookAt(0,0,0); camera.updateMatrixWorld();
 for(const size of [280,390,800]) for(const layout of Object.values(LAYOUTS)) for(const viewer of [0,1]) {
  const art=boardArt(layout);
  const rect={left:15,top:90,width:size,height:size},scale=5/Math.max(art.width,art.height);
  for(const {x,y} of art.spots) {
   const [sx,sy]=artPosition(art,x,y,viewer);
   const projected=new Vector3(sx*scale,0.08*scale,sy*scale).project(camera);
   const hit=pickBoardCell(camera,rect,rect.left+(projected.x+1)*size/2,rect.top+(1-projected.y)*size/2,layout,viewer);
   assert.deepEqual(hit,{x,y});
  }
  if(layout.id===6) {
   const center=new Vector3(0,0.08*scale,0).project(camera);
   assert.equal(pickBoardCell(camera,rect,rect.left+(center.x+1)*size/2,rect.top+(1-center.y)*size/2,layout,viewer),null);
   assert.equal(art.segments.length,34);
  }
  assert.equal(pickBoardCell(camera,rect,14,100,layout,viewer),null);
  assert.equal(pickBoardCell(camera,rect,20,90+size,layout,viewer),null);
 }
});
