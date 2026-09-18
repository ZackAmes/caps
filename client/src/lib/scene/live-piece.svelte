<script lang="ts">
    import { untrack } from 'svelte';
    import { T, useTask } from '@threlte/core';
    import { HTML, type EventMap } from '@threlte/extras';
    import { prefersReducedMotion } from 'svelte/motion';
    import { cubicInOut } from 'svelte/easing';
    import { pieceSymbol } from '$lib/game/presentation';
    import { movementRoute, pointAlong } from '$lib/game/motion';
    import type { LayoutConfig, Position } from '@caps/game-core/board';
    import type { ChainCap } from '@caps/game-core/types';
    let { cap, x, z, layout, viewer, selected, onhover }: {cap:ChainCap; x:number; z:number; layout:LayoutConfig; viewer:number|null; selected:boolean; onhover:(id:number|null)=>void} = $props();
    let px = $state(untrack(() => x)), pz = $state(untrack(() => z));
    let lift = $state(0), moving = $state(false), arrival = $state(0), hit = $state(1);
    let change = $state(''), hurt = $state(false);
    let path: Position[] = [], started = 0, duration = 400, hitStarted = 0;
    const born = performance.now();
    let previous = untrack(() => ({x:cap.x!,y:cap.y!,layout,viewer,health:cap.health,shield:cap.shield}));
    $effect(() => {
        const next = {x:cap.x!,y:cap.y!,layout,viewer,health:cap.health,shield:cap.shield};
        const targetX = x, targetZ = z, reduced = prefersReducedMotion.current;
        untrack(() => {
            if (next.layout !== previous.layout || next.viewer !== previous.viewer || reduced) {
                px = targetX; pz = targetZ; moving = false; lift = 0;
            } else if (next.x !== previous.x || next.y !== previous.y) {
                path = movementRoute(layout, [previous.x,previous.y], [next.x,next.y], viewer);
                // A new plan can interrupt an in-flight glide without snapping back to its start.
                path[0] = [px,pz];
                duration = Math.min(680, 320 + (path.length - 2) * 85);
                started = performance.now(); moving = true;
            }
            const hp = next.health - previous.health, shield = next.shield - previous.shield;
            if (hp || shield) {
                change = hp ? `${hp > 0 ? '+' : ''}${hp}` : `${shield > 0 ? '+' : ''}${shield} ⛨`;
                hurt = hp < 0 || shield < 0; hit = 0; hitStarted = performance.now();
            }
            previous = next;
        });
    });
    useTask(() => {
        const now = performance.now();
        arrival = Math.min(1, (now - born) / 240);
        if (moving) {
            const progress = Math.min(1, (now - started) / duration);
            [px,pz] = pointAlong(path,cubicInOut(progress));
            lift = Math.sin(progress * Math.PI) * 0.16;
            if (progress === 1) { moving = false; lift = 0; }
        }
        if (hit < 1) hit = Math.min(1,(now - hitStarted) / 850);
    }, {running:() => moving || arrival < 1 || hit < 1});
    let scale = $derived(prefersReducedMotion.current ? 1 : 0.65 + 0.35 * (1 - (1 - arrival) ** 3));
</script>
<T.Group position={[px,0.27 + lift,pz]} {scale}
    onpointerenter={(event:EventMap['onpointerenter']) => { if (event.nativeEvent.pointerType === 'mouse') onhover(cap.id); }}
    onpointerleave={() => onhover(null)}>
    <T.Mesh>
        <T.CylinderGeometry args={[0.26,0.32,0.34,24]} />
        <T.MeshStandardMaterial color={cap.playerSlot === 0 ? '#51a5ff' : '#ff7185'} roughness={0.35} metalness={0.15}
            emissive={hurt ? '#f43f5e' : '#34d399'} emissiveIntensity={prefersReducedMotion.current ? 0 : Math.max(0,1-hit*2)*0.65} />
    </T.Mesh>
    {#if selected || cap.shield > 0}
        <T.Mesh position={[0,-0.15,0]} rotation={[-Math.PI/2,0,0]}><T.RingGeometry args={[0.34,0.4,32]} /><T.MeshBasicMaterial color={selected ? '#ffffff' : '#93c5fd'} /></T.Mesh>
    {/if}
    <HTML position={[0,0.4,0]} center pointerEvents="none" zIndexRange={[10,1]}>
        <span class="token" class:selected><b>{pieceSymbol(cap.capType)}</b><small>{cap.health}{cap.shield ? ' ⛨' : ''}{cap.stunnedTurns ? ' ◌' : ''}</small></span>
    </HTML>
    {#if hit < 1}
        <HTML position={[0,0.85 + (prefersReducedMotion.current ? 0 : hit*0.4),0]} center pointerEvents="none" zIndexRange={[11,1]}>
            <span class="change" class:hurt style:opacity={prefersReducedMotion.current ? 1 : Math.min(1,(1-hit)*3)}>{change}</span>
        </HTML>
    {/if}
</T.Group>
<style>
    .token { display:flex; align-items:center; gap:3px; padding:2px 5px; border-radius:7px; background:#0b1220df; color:#f8fafc; border:1px solid #536885; font:16px system-ui; white-space:nowrap; }
    .token.selected { border-color:white; } small { font-size:10px; }
    .change { color:#a7f3d0; font:800 19px system-ui; text-shadow:0 2px 5px #071221,0 0 8px #071221; white-space:nowrap; } .change.hurt { color:#fda4af; }
</style>
