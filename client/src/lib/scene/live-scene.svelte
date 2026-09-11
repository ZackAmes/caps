<script lang="ts">
    import type { PerspectiveCamera } from 'three';
    import LivePiece from './live-piece.svelte';
    import { T } from '@threlte/core';
    import { HTML, interactivity } from '@threlte/extras';
    import { boardArt, artPosition, orient } from '$lib/game/board-art';
    import { goalSlot, isEnergySpace, pathDistance, type LayoutConfig } from '@caps/game-core/board';
    import type { AbilityStack, ChainCap, CapTypeDef } from '@caps/game-core/types';

    let { layout, caps, viewer, definitions, selectedId, targets, focusedCells, stack, oncamera, onhover }: {
        viewer: number | null; layout: LayoutConfig; caps: ChainCap[]; definitions: Map<number, CapTypeDef>;
        selectedId: number | null; targets: Map<string, string>; focusedCells: Set<string>; stack: AbilityStack;
        oncamera:(camera:PerspectiveCamera)=>void; onhover:(id:number|null)=>void;
    } = $props();
    interactivity();
    let art = $derived(boardArt(layout));
    const position = (x:number,y:number) => artPosition(art,x,y,viewer);
    function danger(x: number, y: number) {
        return stack.entries.some(entry => {
            if (entry.impact.kind !== 'Damage') return false;
            const s = entry.impact.selection;
            if (s.kind === 'Row') return s.index === y;
            if (s.kind === 'Column') return s.index === x;
            if (s.kind === 'Piece') return caps.some(c => c.id === s.id && c.x === x && c.y === y);
            return pathDistance(layout, [s.x, s.y], [x, y]) <= s.radius;
        });
    }
    const colors: Record<string, string> = {move: '#14b8a6', fight: '#e45b62', ability: '#a78bfa'};
</script>

<T.PerspectiveCamera makeDefault position={[0, 7.8, 5.5]} fov={43} oncreate={(camera) => { camera.lookAt(0, 0, 0); oncamera(camera); }} />
<T.AmbientLight intensity={1.4} />
<T.DirectionalLight position={[-3, 8, 4]} intensity={2.2} />
<T.DirectionalLight position={[5, 3, -4]} intensity={0.8} color="#8baaff" />
<T.Group scale={5 / Math.max(art.width, art.height)}>
<T.Mesh position={[0,-0.14,0]} rotation={[-Math.PI/2,0,0]}>
    <T.PlaneGeometry args={[art.width+0.3,art.height+0.3]} />
    <T.MeshStandardMaterial color="#101d2b" roughness={0.95} />
</T.Mesh>

{#each art.segments as segment}
    {@const a = orient(segment.from,viewer)}
    {@const b = orient(segment.to,viewer)}
    <T.Mesh position={[(a[0]+b[0])/2,0.015,(a[1]+b[1])/2]} rotation={[0,Math.atan2(b[0]-a[0],b[1]-a[1]),0]}>
        <T.BoxGeometry args={[0.045,0.02,Math.hypot(b[0]-a[0],b[1]-a[1])]} />
        <T.MeshBasicMaterial color="#617f92" />
    </T.Mesh>
{/each}

{#each art.spots as tile (`${tile.x},${tile.y}`)}
    {@const p = position(tile.x,tile.y)}
    {@const target = targets.get(`${tile.x},${tile.y}`)}
    {@const goal = goalSlot(layout,tile.x,tile.y)}
    {@const energy = isEnergySpace(layout,tile.x,tile.y)}
    {@const threatened = danger(tile.x,tile.y)}
    {@const color = target ? colors[target] : focusedCells.has(`${tile.x},${tile.y}`) ? '#a78bfa' : goal === 0 ? '#64b5ff' : goal === 1 ? '#ff8798' : energy ? '#e7c57b' : '#90afbf'}
    <T.Mesh position={[p[0],0,p[1]]}>
        <T.CylinderGeometry args={[0.35,0.4,0.16,40]} />
        <T.MeshStandardMaterial color={target ? colors[target] : '#203444'} roughness={0.6} metalness={0.15} />
    </T.Mesh>
    <T.Mesh position={[p[0],0.085,p[1]]} rotation={[-Math.PI/2,0,0]}>
        <T.RingGeometry args={[0.30,0.345,40]} />
        <T.MeshBasicMaterial color={color} />
    </T.Mesh>
    {#if goal !== null || energy}
        <HTML position={[p[0],0.1,p[1]]} center pointerEvents="none" zIndexRange={[8,1]}>
            <span class="spot-mark" style:color={color}>{goal !== null ? '◇' : 'ϟ'}</span>
        </HTML>
    {/if}
    {#if threatened}
        <T.Mesh position={[p[0],0.095,p[1]]} rotation={[-Math.PI/2,0,0]}>
            <T.RingGeometry args={[0.41,0.46,40]} /><T.MeshBasicMaterial color="#ffb547" />
        </T.Mesh>
    {/if}
{/each}

{#each caps.filter(c => !c.dead && c.x !== null && c.y !== null) as cap (cap.id)}
    {@const p = position(cap.x!,cap.y!)}
    <LivePiece {cap} x={p[0]} z={p[1]} selected={cap.id === selectedId} {onhover} />
{/each}
</T.Group>
<style>
    .spot-mark { font:700 20px system-ui; text-shadow:0 0 8px currentColor; }
</style>
