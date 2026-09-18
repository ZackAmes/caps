<script lang="ts">
    import type { CapTypeDef } from '@caps/game-core/types';
    import { moveDigest, type TurnNotice } from './motion';
    let {notice,definitions,viewer,solo,oninspect}: {notice:TurnNotice; definitions:Map<number,CapTypeDef>;viewer:number|null;solo:boolean;oninspect:()=>void} = $props();
    let digest = $derived(moveDigest(notice.actions,notice.before,definitions));
    let actor = $derived(solo || viewer === null ? `P${notice.playerSlot+1}` : 'Opponent');
    let phase = $derived(({pending:'Confirming',confirmed:'Last move',cancelled:'Not applied',expired:'Checking…'})[notice.phase]);
</script>
<div class="move-notice" aria-live="polite" aria-atomic="true">
    <button onclick={oninspect} aria-label={`${actor}: ${digest.title}, ${digest.detail}${digest.extra ? `, plus ${digest.extra} more actions` : ''}. ${phase}. View turn details.`}>
        <span class="symbol" aria-hidden="true">{digest.icon}</span>
        <span class="description"><span class="actor">{actor} · {digest.title}</span><strong>{digest.detail}{#if digest.extra}<small> +{digest.extra}</small>{/if}</strong></span>
        <span class="phase" class:pending={notice.phase === 'pending'}><i aria-hidden="true"></i>{phase}</span>
        <span class="more" aria-hidden="true">›</span>
    </button>
</div>
<style>
    .move-notice { width:min(100%,620px); margin:0 auto; padding:0 10px 5px; box-sizing:border-box; }
    button { display:flex; align-items:center; gap:9px; width:100%; min-height:44px; padding:5px 9px; border:1px solid #38546b; border-radius:12px; background:linear-gradient(110deg,#193346e8,#132234e8); color:#d9edf7; cursor:pointer; text-align:left; font:inherit; }
    .symbol { display:grid; place-items:center; flex:0 0 28px; width:28px; height:28px; border-radius:8px; background:#274353; color:#9ee7f3; font-size:20px; }
    .description { display:flex; flex:1; min-width:0; flex-direction:column; gap:2px; }
    .actor { color:#9bb3c7; font-size:10px; overflow:hidden; white-space:nowrap; text-overflow:ellipsis; }
    strong { font-size:12px; line-height:16px; font-weight:600; overflow:hidden; white-space:nowrap; text-overflow:ellipsis; }
    small { color:#bca5e8; font-size:10px; }
    .phase { display:flex; align-items:center; gap:5px; color:#94abc0; font-size:10px; white-space:nowrap; }
    i { width:5px; height:5px; border-radius:50%; background:#73c8ab; } .pending { color:#e6cd94; } .pending i { background:#e6cd94; animation:breathe 1.5s ease-in-out infinite; }
    .more { color:#9ab9ce; font-size:20px; } button:focus-visible { outline:2px solid #a5def7; outline-offset:1px; }
    @keyframes breathe { 50% { opacity:0.35; } }
    @media(prefers-reduced-motion:reduce) { .pending i { animation:none; } }
</style>
