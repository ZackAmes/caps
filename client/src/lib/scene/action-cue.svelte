<script lang="ts">
    import { T, useTask } from '@threlte/core';
    import { prefersReducedMotion } from 'svelte/motion';
    import { boardArt, artPosition } from '$lib/game/board-art';
    import { movementRoute, type BoardCue } from '$lib/game/motion';
    import type { LayoutConfig } from '@caps/game-core/board';
    let {cue,layout,viewer}: {cue:BoardCue;layout:LayoutConfig;viewer:number|null} = $props();
    const born = performance.now();
    let progress = $state(0);
    useTask(() => { progress = Math.min(1,(performance.now()-born)/1000); }, {running:() => progress < 1});
    let art = $derived(boardArt(layout));
    let origin = $derived(cue.from && layout.isWalkable(...cue.from) ? artPosition(art,...cue.from,viewer) : null);
    let targets = $derived(cue.cells.filter(([x,y]) => layout.isWalkable(x,y)).map(p => artPosition(art,...p,viewer)));
    let trail = $derived(cue.kind === 'move' && origin && cue.from && targets.length && cue.cells[0] ? movementRoute(layout,cue.from,cue.cells[0],viewer) : origin && targets[0] ? [origin,targets[0]] : []);
    let opacity = $derived(prefersReducedMotion.current ? 0.65 : (1-progress)*0.9);
    let radius = $derived(prefersReducedMotion.current ? 1.1 : 0.75+progress*0.9);
</script>
{#if progress < 1}
    {#each targets as point}
        <T.Mesh position={[point[0],0.13,point[1]]} rotation={[-Math.PI/2,0,0]} scale={radius}>
            <T.RingGeometry args={[0.35,0.41,32]} /><T.MeshBasicMaterial color={cue.color} transparent {opacity} depthWrite={false} />
        </T.Mesh>
    {/each}
    {#if origin && cue.kind !== 'move' && cue.kind !== 'deploy'}
        <T.Mesh position={[origin[0],0.14,origin[1]]} rotation={[-Math.PI/2,0,0]} scale={radius*1.25}>
            <T.RingGeometry args={[0.33,0.39,32]} /><T.MeshBasicMaterial color={cue.color} transparent {opacity} depthWrite={false} />
        </T.Mesh>
    {/if}
    {#each trail.slice(1) as point, i}
        {@const a = trail[i]}
        <T.Mesh position={[(a[0]+point[0])/2,0.16,(a[1]+point[1])/2]} rotation={[0,Math.atan2(point[0]-a[0],point[1]-a[1]),0]}>
            <T.BoxGeometry args={[0.045,0.035,Math.hypot(point[0]-a[0],point[1]-a[1])]} /><T.MeshBasicMaterial color={cue.color} transparent opacity={opacity*0.7} depthWrite={false} />
        </T.Mesh>
    {/each}
{/if}
