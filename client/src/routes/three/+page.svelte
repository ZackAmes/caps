<script lang="ts">
    import { Canvas } from '@threlte/core';
    import { T } from '@threlte/core';
    import { OrbitControls } from '@threlte/extras';
    import Board from '$lib/scene/board.svelte';
    import Pieces, { type ScenePiece } from '$lib/scene/pieces.svelte';
    import {
        LAYOUT_PERIMETER_5X5,
        LAYOUT_CROSS_5X5,
        LAYOUTS,
        getLayout,
    } from '$lib/dojo/client';

    let selectedLayout = $state<number>(LAYOUT_PERIMETER_5X5);
    let layout = $derived(getLayout(selectedLayout));

    // Demo pieces positioned on valid track spots
    let demoPieces = $derived<ScenePiece[]>([
        { x: layout.p1Deploy[0], y: layout.p1Deploy[1], color: '#3b82f6', isTower: true },
        { x: 0, y: 0, color: '#3b82f6', isTower: false },
        { x: 4, y: 0, color: '#3b82f6', isTower: false },
        { x: layout.p2Deploy[0], y: layout.p2Deploy[1], color: '#ef4444', isTower: true },
        { x: 0, y: 4, color: '#ef4444', isTower: false },
        { x: 4, y: 4, color: '#ef4444', isTower: false },
    ]);
</script>

<div class="view-3d">
    <div class="overlay">
        <label for="layout-select">3D Preview Layout:</label>
        <select id="layout-select" bind:value={selectedLayout}>
            {#each Object.values(LAYOUTS) as l}
                <option value={l.id}>{l.name}</option>
            {/each}
        </select>
    </div>

    <Canvas>
        <T.PerspectiveCamera makeDefault position={[0, 7, 7]} fov={45}>
            <OrbitControls maxPolarAngle={Math.PI / 2.1} minDistance={4} maxDistance={14} />
        </T.PerspectiveCamera>

        <Board layoutId={selectedLayout} size={1} />
        <Pieces pieces={demoPieces} width={layout.width} height={layout.height} />
    </Canvas>
</div>

<style>
    .view-3d {
        width: 100vw;
        height: 100vh;
        position: relative;
        background: #0f172a;
    }
    .overlay {
        position: absolute;
        top: 1rem;
        left: 1rem;
        z-index: 10;
        background: rgba(15, 23, 42, 0.85);
        color: #f8fafc;
        padding: 0.6rem 1rem;
        border-radius: 8px;
        backdrop-filter: blur(8px);
        border: 1px solid #334155;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-family: system-ui, sans-serif;
    }
    select {
        background: #1e293b;
        color: #f8fafc;
        border: 1px solid #475569;
        padding: 0.3rem 0.6rem;
        border-radius: 6px;
    }
</style>
