import { Plane, Raycaster, Vector2, Vector3, type Camera } from 'three';
import { boardArt, artPosition } from './board-art';
import type { LayoutConfig } from '@caps/game-core/board';

/** Pointer coordinates to canonical map coordinates, including the player's view rotation. */
export function pickBoardCell(camera: Camera, rect: {left:number;top:number;width:number;height:number}, px:number, py:number, layout:LayoutConfig, viewer:number|null) {
    if (rect.width <= 0 || rect.height <= 0 || px < rect.left || py < rect.top || px >= rect.left+rect.width || py >= rect.top+rect.height) return null;
    const art = boardArt(layout);
    const scale = 5 / Math.max(art.width,art.height);
    const ray = new Raycaster();
    camera.updateMatrixWorld();
    ray.setFromCamera(new Vector2((px-rect.left)/rect.width*2-1, 1-(py-rect.top)/rect.height*2),camera);
    const point = ray.ray.intersectPlane(new Plane(new Vector3(0,1,0),-0.08*scale),new Vector3());
    if (!point) return null;
    let best: {x:number;y:number} | null = null, distance = 0.48;
    for(const spot of art.spots) {
        const [x,y]=artPosition(art,spot.x,spot.y,viewer);
        const d=Math.hypot(point.x/scale-x,point.z/scale-y);
        if(d<distance){distance=d;best={x:spot.x,y:spot.y};}
    }
    return best;
}
