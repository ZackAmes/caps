import { LAYOUT_DUEL_RING, type LayoutConfig, type Position } from '@caps/game-core/board';

export interface ArtSpot { x:number; y:number; px:number; py:number }
export interface ArtSegment { from:Position; to:Position }
export interface BoardArt { width:number; height:number; spots:ArtSpot[]; segments:ArtSegment[] }

// Frontend-only placement. Logical coordinates still identify spots in actions and abilities.
// Ring spots can be moved freely here without changing the movement graph or contracts.
const ringPositions: Record<string,Position> = {};
for (const y of [0,8]) for(let x=0;x<7;x++) ringPositions[`${x},${y}`]=[x-3,y===0?-3.6:3.6];
for (const x of [0,6]) for(const y of [2,4,6]) ringPositions[`${x},${y}`]=[x-3,(y-4)*0.9];
for (const x of [1,3,5]) for(const y of [2,4,6]) {
    if(x!==3 || y!==4) ringPositions[`${x},${y}`]=[(x-3)*0.825,(y-4)*0.825];
}
const cache = new WeakMap<LayoutConfig,BoardArt>();
export function boardArt(layout:LayoutConfig):BoardArt {
    const cached=cache.get(layout); if(cached)return cached;
    const ring=layout.id===LAYOUT_DUEL_RING;
    const point=(x:number,y:number):Position => ring ? ringPositions[`${x},${y}`] : [x-(layout.width-1)/2,y-(layout.height-1)/2];
    const spots:ArtSpot[]=[];
    for(let y=0;y<layout.height;y++)for(let x=0;x<layout.width;x++)if(layout.isWalkable(x,y)) {
        const [px,py]=point(x,y); spots.push({x,y,px,py});
    }
    const segments:ArtSegment[]=[];
    const routes=new Map((layout.connections??[]).map(c=>[[c.from.join(','),c.to.join(',')].sort().join(':'),c]));
    for(const spot of spots)for(const [nx,ny] of layout.neighbors([spot.x,spot.y])) {
        if(spot.y*layout.width+spot.x>=ny*layout.width+nx)continue;
        const route=routes.get([[spot.x,spot.y].join(','),[nx,ny].join(',')].sort().join(':'));
        // The ring uses direct strokes, including the corners. Underlying connector
        // squares are topology authoring data, not mandatory visible tiles or bends.
        const points=ring||!route ? [point(spot.x,spot.y),point(nx,ny)] : [route.from,...route.via,route.to].map(p=>point(...p));
        for(let i=1;i<points.length;i++)segments.push({from:points[i-1],to:points[i]});
    }
    const result={width:ring?7.4:layout.width,height:ring?8.6:layout.height,spots,segments};cache.set(layout,result);return result;
}
export function artPosition(art:BoardArt,x:number,y:number,viewer:number|null=null):Position {
    const spot=art.spots.find(s=>s.x===x&&s.y===y);
    if(!spot)throw new Error(`Missing artwork for spot ${x},${y}`);
    return orient([spot.px,spot.py],viewer);
}
export function orient(point:Position,viewer:number|null):Position {
    return viewer===0 ? [-point[0],-point[1]] : point;
}
