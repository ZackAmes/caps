<script lang="ts">
import {getLayout,LAYOUT_DUEL_RING,type Position} from '@caps/game-core/board';
import {validateBoard,draftLayout,type BoardDraft,type PublishedBoard} from '@caps/game-core/published-board';
import {getPublishedBoard,getBoardCount,publishBoard} from '$lib/dojo/client';
import {boardArt} from './board-art';
let {disabled=false,onselect}:{disabled?:boolean;onselect:(b:PublishedBoard)=>void}=$props();
function template():BoardDraft {
 const l=getLayout(LAYOUT_DUEL_RING),a=boardArt(l);
 return {name:'My Duel Ring',width:l.width,height:l.height,viewWidth:a.width-1,viewHeight:a.height-1,p1Goal:l.p1Deploy,p2Goal:l.p2Deploy,spots:a.spots.map(s=>({at:[s.x,s.y],position:[s.px,s.py],energy:l.energySpaces?.some(p=>p[0]===s.x&&p[1]===s.y)??false})),connections:a.spots.flatMap(s=>l.neighbors([s.x,s.y]).filter(p=>s.y*l.width+s.x<p[1]*l.width+p[0]).map(p=>({from:[s.x,s.y] as Position,to:p})))};
}
let json=$state(JSON.stringify(template(),null,2)),boardId=$state(''),working=$state(false),error=$state(''),notice=$state('');
let recent=$state<PublishedBoard[]>([]);
let parsed=$derived.by(()=>{try{const draft=JSON.parse(json) as BoardDraft;validateBoard(draft);return {draft,art:boardArt(draftLayout(draft,0)),error:''};}catch(e){return {draft:null,art:null,error:e instanceof Error?e.message:String(e)};}});
async function load(id=Number(boardId)){working=true;error='';try{const b=await getPublishedBoard(id);onselect(b);json=JSON.stringify(b.definition,null,2);boardId=String(id);notice=`Selected ${b.definition.name} · #${id}`;}catch(e){error=String(e);}finally{working=false;}}
async function browse(){working=true;error='';try{const count=await getBoardCount();const results=await Promise.allSettled(Array.from({length:Math.min(count,8)},(_,i)=>getPublishedBoard(count-i)));recent=results.flatMap(r=>r.status==='fulfilled'?[r.value]:[]);if(!count)notice='No boards published yet.';}catch(e){error=String(e);}finally{working=false;}}
async function publish(){if(!parsed.draft)return;working=true;error='';notice='Publishing…';try{const b=await publishBoard(parsed.draft);onselect(b);boardId=String(b.id);notice=`Published and selected ${b.definition.name} · #${b.id}`;}catch(e){error=String(e);notice='';}finally{working=false;}}
</script>
<details class="publisher"><summary>Community boards <span>＋</span></summary><div class="content">
<p>Anyone can publish a board. Choose one for your next match, or make your own.</p>
<div class="row"><input aria-label="Board ID" type="number" min="1" placeholder="Board ID" bind:value={boardId}/><button onclick={()=>load()} disabled={disabled||working||!boardId}>Use board</button><button onclick={browse} disabled={disabled||working}>Recent</button></div>
{#each recent as b}<button class="recent" onclick={()=>load(b.id)} disabled={disabled||working}>#{b.id} · {b.definition.name}</button>{/each}
{#if notice}<p role="status">{notice}</p>{/if}{#if error}<p class="error" role="alert">{error}</p>{/if}
<details><summary>Create a board</summary><p>Edit spots, connections, goals and energy spaces. Visual positions are independent of the logical grid; each connection takes one step.</p>
{#if parsed.art}{@const a=parsed.art}<svg viewBox={`${-a.width/2} ${-a.height/2} ${a.width} ${a.height}`} aria-label="Board preview" role="img">{#each a.segments as e}<line x1={e.from[0]} y1={e.from[1]} x2={e.to[0]} y2={e.to[1]}/>{/each}{#each a.spots as s}<circle cx={s.px} cy={s.py} r="0.18" fill="#cbd5e1"/>{/each}</svg>{/if}
<label for="board-json">Board definition (JSON)</label><textarea id="board-json" bind:value={json} spellcheck="false" rows="12"></textarea>
{#if parsed.error}<p class="error">{parsed.error}</p>{/if}<p>Published boards are permanent. Publish a new version to make changes; existing games keep their board.</p><button onclick={publish} disabled={disabled||working||!parsed.draft}>{working?'Please wait…':'Publish & select'}</button></details>
</div></details>
<style>
.publisher{border:1px solid #334155;border-radius:18px;background:#111c30;padding:1rem;color:#e2e8f0}summary{cursor:pointer;font-weight:600;display:flex;justify-content:space-between}.content{padding-top:1rem}p{font-size:.85rem;line-height:1.5;color:#94a3b8}.row{display:flex;gap:.4rem;flex-wrap:wrap}input{min-width:5rem;flex:1;width:6rem}button,input,textarea{background:#1e293b;color:#e2e8f0;border:1px solid #475569;border-radius:8px;padding:.65rem}button{cursor:pointer}button:disabled{opacity:.5;cursor:default}.recent{display:block;margin:.4rem 0;width:100%;text-align:left}textarea{display:block;box-sizing:border-box;width:100%;font:12px monospace;resize:vertical}label{font-size:.8rem}svg{width:100%;height:240px;margin:.5rem 0;background:#0f172a;border-radius:12px}line{stroke:#64748b;stroke-width:.06}.error{color:#fca5a5}details details{margin-top:1rem}
</style>
