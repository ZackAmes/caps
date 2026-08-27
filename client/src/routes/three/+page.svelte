<script lang="ts">
    import { Canvas } from '@threlte/core'
    import { T } from '@threlte/core';
    import Board from '$lib/scene/board.svelte';
    import Pieces from '$lib/scene/pieces.svelte';
    import { PerspectiveCamera } from 'three';
    import { OrbitControls } from '@threlte/extras';
    

    // Example pieces for demonstration
    const examplePieces = [
        { x: 0, y: 0, color: '#ff0000' },
        { x: 3, y: 3, color: '#00ff00' },
        { x: 6, y: 6, color: '#0000ff' },
        { x: 2, y: 4, color: '#ff00ff', height: 1 },
        { x: 4, y: 2, color: '#ffff00' },
    ];
</script>

<Canvas>
    <!-- Camera positioned to view the board -->
    <T.PerspectiveCamera makeDefault position={[8, 8, 8]} fov={50}>
        <OrbitControls />
    </T.PerspectiveCamera>

    <!-- Board with 7x7 grid -->
    <Board size={1} gridSize={7} />

    <!-- Game pieces -->
    <Pieces pieces={examplePieces} tileSize={1} pieceRadius={0.4} />
</Canvas>