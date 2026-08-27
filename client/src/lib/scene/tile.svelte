<script lang="ts">
    import { T } from '@threlte/core';

    interface Props {
        x: number;
        y: number;
        size?: number;
        color?: string;
    }

    let { x, y, size = 1, color = '#f0f0f0' }: Props = $props();

    // Calculate position from grid coordinates
    const posX = (x - 3) * size; // Center the board (0-6 grid -> -3 to 3)
    const posZ = (y - 3) * size;
    const posY = 0; // Tiles are at ground level
</script>

<T.Mesh position={[posX, posY, posZ]}>
    <T.BoxGeometry args={[size * 0.95, 0.1, size * 0.95]} />
    <T.MeshStandardMaterial color={color} />
</T.Mesh>