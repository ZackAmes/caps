<script lang="ts">
    import type { PerspectiveCamera } from 'three';
    import LivePiece from './live-piece.svelte';
    import { T } from '@threlte/core';
    import { HTML, interactivity, type EventMap } from '@threlte/extras';
    import { pathEdges, boardPosition, connectorSquares } from '$lib/game/presentation';
    import { goalSlot, isEnergySpace, pathDistance, type LayoutConfig } from '@caps/game-core/board';
    import type { AbilityStack, ChainCap, CapTypeDef } from '@caps/game-core/types';

    let { layout, caps, viewer, definitions, selectedId, targets, focusedCells, stack, oncamera, onhover }: {
        viewer: number | null; layout: LayoutConfig; caps: ChainCap[]; definitions: Map<number, CapTypeDef>;
        selectedId: number | null; targets: Map<string, string>; focusedCells: Set<string>; stack: AbilityStack;
        oncamera:(camera:PerspectiveCamera)=>void; onhover:(id:number|null)=>void;
    } = $props();
    interactivity();
    let tiles = $derived(Array.from({length: layout.width * layout.height}, (_, i) => ({x: i % layout.width, y: Math.floor(i / layout.width)})));
    let connectors = $derived(connectorSquares(layout));
    const wx = (x: number) => boardPosition(layout,x,0,viewer)[0] - (layout.width - 1) / 2;
    const wz = (y: number) => boardPosition(layout,0,y,viewer)[1] - (layout.height - 1) / 2;
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
<T.Group scale={5 / Math.max(layout.width, layout.height)}>
<T.Mesh position={[0, -0.24, 0]}>
    <T.BoxGeometry args={[layout.width + 0.25, 0.32, layout.height + 0.25]} />
    <T.MeshStandardMaterial color="#101b2e" roughness={0.85} />
</T.Mesh>

{#each tiles as tile (`${tile.x},${tile.y}`)}
    {@const walkable = layout.isWalkable(tile.x, tile.y)}
    {@const target = targets.get(`${tile.x},${tile.y}`)}
    {@const goal = goalSlot(layout,tile.x,tile.y)}
    {@const energy = isEnergySpace(layout,tile.x,tile.y)}
    {@const threatened = walkable && danger(tile.x, tile.y)}
    {@const connector = connectors.has(`${tile.x},${tile.y}`)}
    {#if walkable || !layout.connections?.length || connector}
    <T.Mesh position={[wx(tile.x), walkable ? 0 : -0.09, wz(tile.y)]}>
        <T.BoxGeometry args={[0.91, walkable ? 0.16 : 0.025, 0.91]} />
        <T.MeshStandardMaterial color={target ? colors[target] : focusedCells.has(`${tile.x},${tile.y}`) ? '#7651ae' : goal !== null ? goal === 0 ? '#244b83' : '#783446' : energy ? '#78612c' : walkable ? '#33455f' : connector ? '#26374e' : '#172338'}
            emissive={threatened ? '#e98a19' : target ? colors[target] : '#000000'} emissiveIntensity={threatened ? 0.35 : 0.12} roughness={0.7} />
    </T.Mesh>
    {/if}
    {#if walkable && (goal !== null || energy)}
        <HTML position={[wx(tile.x), 0.12, wz(tile.y) + 0.32]} center pointerEvents="none" zIndexRange={[8, 1]}>
            <span class="tile-label">{goal !== null ? `P${goal + 1} ◇` : '⚡'}</span>
        </HTML>
    {/if}
    {#if threatened}
        <T.Mesh position={[wx(tile.x), 0.095, wz(tile.y)]} rotation={[-Math.PI / 2, 0, 0]}>
            <T.RingGeometry args={[0.36, 0.41, 4]} />
            <T.MeshBasicMaterial color="#ffb547" />
        </T.Mesh>
    {/if}
{/each}

{#each Array.from({length:layout.width}, (_,i)=>i) as x}
    <HTML position={[wx(x),0.12,-layout.height / 2 - 0.13]} center pointerEvents="none" zIndexRange={[8,1]}><span class="axis-label">{String.fromCharCode(65+x)}</span></HTML>
{/each}
{#each Array.from({length:layout.height}, (_,i)=>i) as y}
    <HTML position={[-layout.width / 2 - 0.13,0.12,wz(y)]} center pointerEvents="none" zIndexRange={[8,1]}><span class="axis-label">{y+1}</span></HTML>
{/each}
{#each pathEdges(layout) as edge}
    <T.Mesh position={[wx((edge.x1 + edge.x2) / 2), 0.1, wz((edge.y1 + edge.y2) / 2)]}
        rotation={[0, Math.atan2(edge.x2 - edge.x1, edge.y2 - edge.y1), 0]}>
        <T.BoxGeometry args={[0.04, 0.02, Math.hypot(edge.x2 - edge.x1, edge.y2 - edge.y1)]} />
        <T.MeshBasicMaterial color="#afc3de" />
    </T.Mesh>
{/each}

{#each caps.filter(c => !c.dead && c.x !== null && c.y !== null) as cap (cap.id)}
    <LivePiece {cap} x={wx(cap.x!)} z={wz(cap.y!)} selected={cap.id === selectedId} {onhover} />
{/each}

</T.Group>

<style>
    .axis-label { color:#d1dcec; font:700 11px system-ui; }
    .tile-label { color: #dde8f9; font: 700 8px system-ui; white-space: nowrap; text-shadow: 0 1px 3px #000; }
</style>
