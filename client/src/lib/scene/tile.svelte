<script lang="ts">
    import { T } from '@threlte/core';

    interface Props {
        x: number;
        y: number;
        width?: number;
        height?: number;
        size?: number;
        color?: string;
        isWalkable?: boolean;
        isDeploy?: boolean;
    }

    let {
        x,
        y,
        width = 5,
        height = 5,
        size = 1,
        color = '#f0f0f0',
        isWalkable = true,
        isDeploy = false,
    }: Props = $props();

    // Dynamically center based on board dimensions
    let posX = $derived((x - (width - 1) / 2) * size);
    let posZ = $derived((y - (height - 1) / 2) * size);
    let tileHeight = $derived(isWalkable ? 0.1 : 0.02);
</script>

<T.Mesh position={[posX, isWalkable ? 0 : -0.04, posZ]}>
    <T.BoxGeometry args={[size * 0.95, tileHeight, size * 0.95]} />
    <T.MeshStandardMaterial
        color={isDeploy ? '#3b82f6' : isWalkable ? color : '#e2e8f0'}
        opacity={isWalkable ? 1 : 0.3}
        transparent={!isWalkable}
    />
</T.Mesh>
