<script lang="ts">
    import type { BoardCue } from '$lib/game/motion';
    import { onMount } from 'svelte';
    import { pickBoardCell } from '$lib/game/picking';
    import type { PerspectiveCamera } from 'three';
    import { Canvas } from '@threlte/core';
    import LiveScene from './live-scene.svelte';
    import type { LayoutConfig } from '@caps/game-core/board';
    import type { AbilityStack, ChainCap, CapTypeDef } from '@caps/game-core/types';

    let { layout, caps, viewer, definitions, selectedId, targets, focusedCells, stack, cues, onhover, onfailure, onpickready, onpointerdown, onpointermove, onpointerup, onpointercancel }: {
        viewer: number | null; layout: LayoutConfig; caps: ChainCap[]; definitions: Map<number, CapTypeDef>;
        selectedId: number | null; targets: Map<string, string>; focusedCells: Set<string>; stack: AbilityStack; cues: BoardCue[];
        onpickready:(pick:((x:number,y:number)=>{x:number;y:number}|null)|null)=>void;
        onpointerdown:(e:PointerEvent)=>void; onpointermove:(e:PointerEvent)=>void; onpointerup:(e:PointerEvent)=>void; onpointercancel:()=>void; onfailure: () => void; onhover:(id:number|null)=>void;
    } = $props();
    let viewport: HTMLDivElement;
    let camera: PerspectiveCamera | undefined;
    onMount(() => {
        // Context loss does not bubble; capture it from the child canvas.
        const element = viewport;
        onpickready((x,y) => camera ? pickBoardCell(camera,element.getBoundingClientRect(),x,y,layout,viewer) : null);
        element.addEventListener('webglcontextlost', onfailure, true);
        return () => { onpickready(null); element.removeEventListener('webglcontextlost', onfailure, true); };
    });
</script>

<div class="viewport" bind:this={viewport} {onpointerdown} {onpointermove} {onpointerup} {onpointercancel} onlostpointercapture={onpointercancel} role="application" aria-label="Interactive game board">
    <Canvas dpr={1.5}>
        <LiveScene {viewer} {layout} {caps} {definitions} {selectedId} {targets} {focusedCells} {stack} {cues} oncamera={(value) => camera = value} {onhover} />
    </Canvas>
</div>

<style>
    .viewport { width: min(100cqw, 100cqh); height: min(100cqw, 100cqh); min-height: 0; touch-action: none; overflow: hidden; border-radius: 12px; background: transparent; }
</style>
