<script lang="ts">
    import { T } from '@threlte/core';
    import Tile from './tile.svelte';
    import { getLayout, LAYOUT_PERIMETER_5X5, type LayoutConfig } from '$lib/dojo/client';

    interface Props {
        size?: number;
        layoutId?: number;
    }

    let { size = 1, layoutId = LAYOUT_PERIMETER_5X5 }: Props = $props();

    let layout = $derived<LayoutConfig>(getLayout(layoutId));

    let tiles = $derived(
        Array.from({ length: layout.height }, (_, y) =>
            Array.from({ length: layout.width }, (_, x) => ({
                x,
                y,
                isWalkable: layout.isWalkable(x, y),
                isDeploy: (x === layout.p1Deploy[0] && y === layout.p1Deploy[1]) ||
                          (x === layout.p2Deploy[0] && y === layout.p2Deploy[1]),
            }))
        ).flat()
    );

    const getTileColor = (x: number, y: number) => {
        return (x + y) % 2 === 0 ? '#ffffff' : '#f1f5f9';
    };
</script>

<T.DirectionalLight position={[10, 10, 5]} intensity={1} />
<T.AmbientLight intensity={0.6} />

{#each tiles as tile}
    <Tile
        x={tile.x}
        y={tile.y}
        width={layout.width}
        height={layout.height}
        {size}
        color={getTileColor(tile.x, tile.y)}
        isWalkable={tile.isWalkable}
        isDeploy={tile.isDeploy}
    />
{/each}
