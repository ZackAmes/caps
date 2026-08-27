<script lang="ts">
    import { T } from '@threlte/core';

    interface Piece {
        x: number;
        y: number;
        color: string;
        height?: number;
    }

    interface Props {
        pieces?: Piece[];
        tileSize?: number;
        pieceRadius?: number;
    }

    let { pieces = [], tileSize = 1, pieceRadius = 0.4 }: Props = $props();

    // Convert grid coordinates to world position
    const gridToWorld = (x: number, y: number, height: number = 0) => {
        return [
            (x - 3) * tileSize,
            0.5 + height * 0.3, // Piece height from ground
            (y - 3) * tileSize
        ];
    };
</script>

{#each pieces as piece, i}
    {@const [posX, posY, posZ] = gridToWorld(piece.x, piece.y, piece.height ?? 0)}
    <T.Mesh position={[posX, posY, posZ]}>
        <T.CylinderGeometry args={[pieceRadius, pieceRadius, 0.4, 32]} />
        <T.MeshStandardMaterial color={piece.color} />
    </T.Mesh>
{/each}
