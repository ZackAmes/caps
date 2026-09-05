<script lang="ts">
    import { T } from '@threlte/core';

    export interface ScenePiece {
        x: number;
        y: number;
        color: string;
        health?: number;
    }

    interface Props {
        pieces?: ScenePiece[];
        width?: number;
        height?: number;
        tileSize?: number;
        pieceRadius?: number;
    }

    let {
        pieces = [],
        width = 5,
        height = 5,
        tileSize = 1,
        pieceRadius = 0.38,
    }: Props = $props();

    const gridToWorld = (x: number, y: number): [number, number, number] => {
        const posX = (x - (width - 1) / 2) * tileSize;
        const posZ = (y - (height - 1) / 2) * tileSize;
        const posY = 0.25;
        return [posX, posY, posZ];
    };
</script>

{#each pieces as piece}
    {@const [posX, posY, posZ] = gridToWorld(piece.x, piece.y)}
    <T.Group position={[posX, posY, posZ]}>
            <T.Mesh>
                <T.CylinderGeometry args={[pieceRadius, pieceRadius, 0.35, 32]} />
                <T.MeshStandardMaterial color={piece.color} roughness={0.3} />
            </T.Mesh>
    </T.Group>
{/each}
