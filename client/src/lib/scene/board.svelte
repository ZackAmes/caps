<script lang="ts">
    import { T } from '@threlte/core';
    import Tile from './tile.svelte';
    import { DirectionalLight, AmbientLight } from 'three';

    interface Props {
        size?: number;
        gridSize?: number;
    }

    let { size = 1, gridSize = 7 }: Props = $props();

    // Generate 7x7 grid of tiles
    const tiles = Array.from({ length: gridSize }, (_, y) =>
        Array.from({ length: gridSize }, (_, x) => ({ x, y }))
    ).flat();

    // Checkerboard pattern colors
    const getTileColor = (x: number, y: number) => {
        return (x + y) % 2 === 0 ? '#e8e8e8' : '#d0d0d0';
    };
</script>

<!-- Directional light for better visibility -->
<T.DirectionalLight position={[10, 10, 5]} intensity={1} />
<T.AmbientLight intensity={0.5} />

<!-- Render all tiles -->
{#each tiles as tile}
    <Tile x={tile.x} y={tile.y} {size} color={getTileColor(tile.x, tile.y)} />
{/each}