import {createLayout, pathDistances, type LayoutConfig, type Position} from './board';

export interface BoardDraft {
  name:string; width:number; height:number; viewWidth:number; viewHeight:number;
  p1Goal:Position; p2Goal:Position;
  spots:{at:Position; position:Position; energy?:boolean}[];
  connections:{from:Position; to:Position; via?:Position[]}[];
}
export interface PublishedBoard { id:number; creator:string; definition:BoardDraft; layout:LayoutConfig }
const same=(a:Position,b:Position)=>a[0]===b[0]&&a[1]===b[1];
const fixed=(n:number)=>Math.round(n*1000);
function assert(ok:unknown,message:string):asserts ok {if(!ok)throw new Error(message);}
export function validateBoard(d:BoardDraft):void {
  assert(typeof d.name==='string'&&new TextEncoder().encode(d.name).length>0&&new TextEncoder().encode(d.name).length<=64,'Name must be 1–64 UTF-8 bytes');
  assert([d.width,d.height].every(n=>Number.isInteger(n)&&n>0&&n<=15),'Logical dimensions must be 1–15');
  assert([d.viewWidth,d.viewHeight].every(n=>Number.isFinite(n)&&n>=1&&fixed(n)<=65535),'Visual dimensions must be 1–65.535');
  assert(Array.isArray(d.spots)&&d.spots.length>=2&&d.spots.length<=64&&Array.isArray(d.connections)&&d.connections.length<=128,'Limit: 2–64 spots and 128 connections');
  const logical=(p:Position)=>Array.isArray(p)&&p.length===2&&p.every(Number.isInteger)&&p[0]>=0&&p[0]<d.width&&p[1]>=0&&p[1]<d.height;
  const visual=(p:Position)=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&Math.abs(p[0])<=d.viewWidth/2&&Math.abs(p[1])<=d.viewHeight/2;
  const keys=new Set<string>(),positions=new Set<string>();
  for(const s of d.spots){assert(logical(s.at)&&visual(s.position),'Spot outside declared bounds');assert(!keys.has(s.at.join(',')),'Duplicate logical spot');keys.add(s.at.join(','));const pos=[fixed(s.position[0]+d.viewWidth/2),fixed(s.position[1]+d.viewHeight/2)].join(',');assert(!positions.has(pos),'Duplicate visual position');positions.add(pos);assert(s.energy===undefined||typeof s.energy==='boolean','Energy must be boolean');}
  assert(logical(d.p1Goal)&&logical(d.p2Goal)&&keys.has(d.p1Goal.join(','))&&keys.has(d.p2Goal.join(','))&&!same(d.p1Goal,d.p2Goal),'Goals must be distinct playable spots');
  const edges=new Set<string>();
  for(const e of d.connections){assert(logical(e.from)&&logical(e.to)&&keys.has(e.from.join(','))&&keys.has(e.to.join(','))&&!same(e.from,e.to),'Invalid connection endpoints');const key=[e.from.join(','),e.to.join(',')].sort().join(':');assert(!edges.has(key),'Duplicate connection');edges.add(key);assert(e.via===undefined||Array.isArray(e.via),'Waypoints must be an array');assert((e.via??[]).length<=8&&(e.via??[]).every(visual),'Waypoints exceed bounds or limit of 8');}
  const layout=draftLayout(d,0);
  assert(pathDistances(layout,d.p1Goal).size===d.spots.length,'All spots must be connected');
}
export function draftLayout(d:BoardDraft,id:number):LayoutConfig {
  const layout=createLayout({id:256+id,name:d.name,description:`Community board #${id}`,width:d.width,height:d.height,p1Deploy:d.p1Goal,p2Deploy:d.p2Goal,energySpaces:d.spots.filter(s=>s.energy).map(s=>s.at),artwork:{width:d.viewWidth+1,height:d.viewHeight+1,spots:d.spots.map(s=>({at:s.at,position:s.position})),routes:d.connections.map(e=>({from:e.from,to:e.to,via:e.via??[]}))}},d.connections.map(e=>[e.from,e.to]));
  return layout;
}
function encodeText(text:string):(number|string)[] {
  const bytes=new TextEncoder().encode(text),words:string[]=[];
  const word=(part:Uint8Array)=>'0x'+([...part].map(b=>b.toString(16).padStart(2,'0')).join('')||'0');
  for(let i=0;i+31<=bytes.length;i+=31)words.push(word(bytes.slice(i,i+31)));
  return [words.length,...words,word(bytes.slice(words.length*31)),bytes.length%31];
}
export function encodeBoard(d:BoardDraft):(number|string)[] {
  validateBoard(d);
  const visual=(p:Position)=>[fixed(p[0]+d.viewWidth/2),fixed(p[1]+d.viewHeight/2)];
  return [...encodeText(d.name),d.width,d.height,fixed(d.viewWidth),fixed(d.viewHeight),...d.p1Goal,...d.p2Goal,d.spots.length,...d.spots.flatMap(s=>[...s.at,...visual(s.position),s.energy?1:0]),d.connections.length,...d.connections.flatMap(e=>[d.spots.findIndex(s=>same(s.at,e.from)),d.spots.findIndex(s=>same(s.at,e.to)),(e.via??[]).length,...(e.via??[]).flatMap(visual)])];
}
export function decodeBoard(raw:string[]):PublishedBoard|null {
  let i=0;
  const take=()=>{assert(i<raw.length,'Truncated board');return raw[i++];};
  const number=()=>{const n=Number(BigInt(take()));assert(Number.isSafeInteger(n)&&n>=0,'Invalid board integer');return n;};
  const tag=number();assert(tag<=1,'Invalid board option');
  if(tag===1){assert(i===raw.length,'Malformed missing board');return null;}
  const id=number(),creator=take(),count=number(),bytes:number[]=[];
  assert(count<=2,'Board name too long');
  const append=(word:string,n:number)=>{const hex=BigInt(word).toString(16).padStart(n*2,'0');assert(hex.length<=Math.max(1,n*2),'Invalid text word');for(let k=0;k<n;k++)bytes.push(parseInt(hex.slice(k*2,k*2+2),16));};
  for(let k=0;k<count;k++)append(take(),31);
  const pending=take(),length=number();assert(length<31,'Invalid pending text');append(pending,length);
  let name:string;
  try { name=new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(bytes)); } catch { name=`Board #${id}`; }
  const width=number(),height=number(),viewWidth=number()/1000,viewHeight=number()/1000;
  const p1Goal:Position=[number(),number()],p2Goal:Position=[number(),number()];
  const n=number();assert(n<=64,'Too many spots');
  const spots:BoardDraft['spots']=[];
  for(let k=0;k<n;k++){const at:Position=[number(),number()],position:Position=[number()/1000-viewWidth/2,number()/1000-viewHeight/2],energy=number();assert(energy<=1,'Invalid energy flag');spots.push({at,position,energy:energy===1});}
  const m=number();assert(m<=128,'Too many connections');const connections:BoardDraft['connections']=[];
  for(let k=0;k<m;k++){const a=number(),b=number(),v=number();assert(a<n&&b<n&&v<=8,'Invalid edge');const via:Position[]=[];for(let j=0;j<v;j++)via.push([number()/1000-viewWidth/2,number()/1000-viewHeight/2]);connections.push({from:spots[a].at,to:spots[b].at,via});}
  assert(i===raw.length,'Unexpected board data');const definition={name,width,height,viewWidth,viewHeight,p1Goal,p2Goal,spots,connections};validateBoard(definition);
  return {id,creator,definition,layout:draftLayout(definition,id)};
}
