<script lang="ts">
    import { clockRemaining, clockLabel, type GameClock } from '@caps/game-core/clock';
    import { submissionHasLanded } from '$lib/game/sync';
    import StackPanel from '$lib/game/StackPanel.svelte';
    import TurnHistory from '$lib/game/TurnHistory.svelte';
    import { actionLabel, square } from '$lib/game/history';
    import { onMount } from 'svelte';
    import { dojoConfig } from '$lib/dojo/config';
    import { viewerSlot, pathEdges, connectorSquares, effectTiming, impactFootprint, pieceSymbol } from '$lib/game/presentation';
    import botAccount from '../../../../bot/account.public.json';
    import { previewTurn } from '@caps/game-core/preview';
    import { createGame, createSoloGame, takeTurn, claimTimeout, type TransactionProgress, getGame, getHand, getStack, getCapTypeCached, findLatestGameForPlayer, getGameSnapshot, getClock, getTurnRecord, transactionState } from '$lib/dojo/client';
    import { connect, isDevMode } from '$lib/dojo/account';
    import { getLayout, goalSlot, isEnergySpace, LAYOUT_DUEL_RING, pathDistance, LAYOUTS, LAYOUT_PERIMETER_5X5, type LayoutConfig } from '@caps/game-core/board';
    import { describeImpact } from '@caps/game-core/stack';
    import type { AbilityStack, TurnRecord } from '@caps/game-core/types';
    import { passiveActive, passiveBonus } from '@caps/game-core/passives';
    import { passiveLabel } from '$lib/dojo/labels';
    import type { ChainGame, ChainCap, TurnAction, ChainHand, CapTypeDef } from '@caps/game-core/types';

    let account = $state<string | null>(null);
    let status = $state<string>('Disconnected');
    let errorMsg = $state<string | null>(null);
    let busy = $state<string | null>(null);

    // On-screen log for mobile debugging
    let logLines = $state<string[]>([]);
    let logOpen = $state(false);
    function log(msg: string, kind: 'info' | 'error' = 'info') {
        const t = new Date().toLocaleTimeString([], { hour12: false });
        logLines = [...logLines.slice(-49), `[${t}] ${kind === 'error' ? '\u274c' : '\u00b7'} ${msg}`];
        if (kind === 'error') logOpen = true;
    }

    let addrCopied = $state(false);
    const devMode = isDevMode();

    async function copyAddress() {
        if (!account) return;
        try {
            await navigator.clipboard.writeText(account);
        } catch {
            const ta = document.createElement('textarea');
            ta.value = account;
            ta.style.position = 'fixed';
            ta.style.opacity = '0';
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); } catch { /* ignore */ }
            ta.remove();
        }
        addrCopied = true;
        log('Address copied to clipboard');
        setTimeout(() => { addrCopied = false; }, 1500);
    }

    const savedGameKey = `caps:last-game:${dojoConfig.worldAddress}`;
    let resumeId = $state<number | null>(null);
    let linkCopied = $state(false);
    let boardMode = $state<'3d' | '2d'>('3d');
    let ThreeBoard = $state<typeof import('$lib/scene/live-board.svelte').default | null>(null);
    let boardPicker = $state<((x:number,y:number)=>{x:number;y:number}|null)|null>(null);
    let activePointer: number | null = null;
    let pointerElement: HTMLElement | null = null;
    let boardNotice = $state('');
    function fallbackBoard() {
        boardMode = '2d';
        boardNotice = '3D rendering is unavailable. You can continue playing in 2D.';
    }
    function setBoardMode(mode: '3d' | '2d') {
        onPointerCancel(); boardMode = mode;
        try { localStorage.setItem('caps:board-view', mode); } catch { /* Optional preference. */ }
    }
    onMount(() => {
        try { if (localStorage.getItem('caps:board-view') === '2d') boardMode = '2d'; } catch { /* Optional preference. */ }
        import('$lib/scene/live-board.svelte').then(module => { ThreeBoard = module.default; }).catch(fallbackBoard);
        const tick = setInterval(() => clockTick = performance.now(), 250);
        const linked = Number(new URL(location.href).searchParams.get('game'));
        let saved = 0;
        try { saved = Number(localStorage.getItem(savedGameKey)); } catch { /* Storage may be unavailable. */ }
        const id = linked || saved;
        if (Number.isSafeInteger(id) && id > 0) { resumeId = id; gameIdInput = String(id); }
        return () => clearInterval(tick);
    });
    async function copyGameLink() {
        if (!game) return;
        const url = new URL(location.href); url.searchParams.set('game', String(game.id));
        try { await navigator.clipboard.writeText(url.href); linkCopied = true; }
        catch { errorMsg = 'Copy the game link from your address bar.'; }
    }

    let opponent = $state('');
    let selectedLayout = $state<number>(LAYOUT_DUEL_RING);
    let gameIdInput = $state('1');
    let game = $state<ChainGame | null>(null);

    let clockSample = $state<{clock:GameClock; receivedAt:number} | null>(null);
    let clockTick = $state(0);
    let clockTimes = $derived(clockSample && game ? clockRemaining(clockSample.clock, game.turnCount, game.over,
        clockSample.clock.chainTime + Math.max(0, clockTick - clockSample.receivedAt) / 1000) : null);
    let timedOut = $derived(!!game?.over && !!clockSample?.clock.enabled && clockSample.clock.timedOutSlot < 2);

    let hand = $state<ChainHand | null>(null);
    let opponentHand = $state<ChainHand | null>(null);
    let capDefMap = $state<Map<number, CapTypeDef>>(new Map());
    let abilityTargetMode = $state(false);
    let selectedCapId = $state<number | null>(null);
    let overlay = $state<'stack' | 'history' | 'menu' | null>(null);
    let sheet = $state<HTMLDialogElement>();
    $effect(() => { if (!sheet) return; if (overlay && !sheet.open) sheet.showModal(); else if (!overlay && sheet.open) sheet.close(); });
    function closeOverlay() { overlay = null; stackTargetMode = false; }
    let hoveredCapId = $state<number | null>(null);
    let queuedActions: TurnAction[] = $state([]);
    let pendingStack = $state<AbilityStack>({gameId:0,nextId:0,entries:[]});
    let committing = $state(false);
    let stackTargetMode = $state(false);
    let focusedEffectId = $state<number | null>(null);
    let pendingSubmission = $state<{gameId:number; turn:number; hash:string; confirmed:boolean} | null>(null);
    let syncStage = $state<'idle'|'submitting'|'confirming'|'syncing'>('idle');
    let syncError = $state<string | null>(null);
    let lastSynced = $state<string>('');
    let loadEpoch = 0, submissionEpoch = 0, historyEpoch = 0;
    let historyRecords = $state<TurnRecord[]>([]);
    let historyLoading = $state(false);
    let historyError = $state<string | null>(null);
    let historyGame = 0;
    let historyCursor = $state(0);
    let pendingForGame = $derived(pendingSubmission?.gameId === game?.id ? pendingSubmission : null);
    let selectedActor = $derived(selectedCapId === null ? undefined : capById(selectedCapId));
    let inspectedActor = $derived(selectedActor ?? (hoveredCapId === null ? undefined : capById(hoveredCapId)));

    async function deadline<T>(promise: Promise<T>, ms = 25000): Promise<T> {
        let timer: ReturnType<typeof setTimeout>;
        try { return await Promise.race([promise, new Promise<T>((_, reject) => { timer = setTimeout(() => reject(new Error('The network is taking longer than expected. We will keep checking.')), ms); })]); }
        finally { clearTimeout(timer!); }
    }
    async function loadHistory(id = game?.id, end = game?.turnCount, older = false) {
        if (!id || end === undefined) return;
        const epoch = ++historyEpoch;
        if (historyGame !== id) { historyGame = id; historyRecords = []; historyCursor = end; }
        const stop = older ? historyCursor : end, start = Math.max(0, stop - 4);
        historyLoading = true; historyError = null;
        try {
            const records = await deadline(Promise.all(Array.from({length:stop-start}, (_, i) => getTurnRecord(id, stop-i-1))));
            if (epoch !== historyEpoch || game?.id !== id) return;
            const merged = new Map(historyRecords.map(r => [r.turn, r]));
            for (const record of records) if (record) merged.set(record.turn, record);
            historyRecords = [...merged.values()].sort((a,b) => b.turn-a.turn);
            historyCursor = Math.min(historyCursor, start);
        } catch { if (epoch === historyEpoch) historyError = 'History is temporarily unavailable. Refresh to retry.'; }
        finally { if (epoch === historyEpoch) historyLoading = false; }
    }
    function targetPending(id: number) {
        if (!selectedActor || !canActivateSelected) return;
        const action: TurnAction = {capId:selectedActor.id,kind:'StackAbility',targetId:id};
        try {
            const next = [...queuedActions, action];
            previewTurn(game!, hand, capDefMap, activeLayout, next, pendingStack);
            queuedActions = next; stackTargetMode = false; focusedEffectId = null; overlay = null;
            status = `Planned negation of effect #${id}`; errorMsg = null;
        } catch (error) { errorMsg = error instanceof Error ? error.message : String(error); }
    }

    let mySlot = $derived(game ? viewerSlot(game, account) : null);
    let canClaimTimeout = $derived(!!game && !game.over && mySlot !== null && !isMyTurn() &&
        clockTimes !== null && clockTimes[game.turnCount % 2] <= 0 && !committing && !pendingForGame && busy === null);

    let otherHand = $derived(game && mySlot === game.turnCount % 2 ? opponentHand : hand);
    let activeLayout = $derived<LayoutConfig>(getLayout(game ? game.layout : selectedLayout));
    let connectorCells = $derived(connectorSquares(activeLayout));
    let isSolo = $derived<boolean>(!!game && game.player1 === game.player2);

    let preview = $derived(game ? previewTurn(game, hand, capDefMap, activeLayout, queuedActions, pendingStack) : null);
    let remainingEnergy = $derived(preview?.energy ?? 0);
    let simCaps = $derived(preview?.caps ?? []);
    let canActivateSelected = $derived(!!selectedActor && canAct() && isMyCap(selectedActor) && selectedActor.x !== null && !selectedActor.stunnedTurns && !preview?.usedAbilities.has(selectedActor.id) && remainingEnergy >= (capDefFor(selectedActor)?.abilityCost ?? Infinity));

    let focusedCells = $derived(impactFootprint(preview?.stack.entries.find(e => e.id === focusedEffectId), simCaps, activeLayout));
    let latestOpponent = $derived(historyRecords.find(r => isSolo || r.playerSlot !== mySlot));
    let sceneTargets = $derived.by(() => {
        const cap = capById(drag?.capId ?? selectedCapId ?? -1);
        if (!cap || !canAct()) return new Map<string, string>();
        if (cap.x === null && (preview?.actions ?? 0) > 0 && isMyCap(cap)) { const [x,y] = deploySpot(); return capAt(x,y) ? new Map<string,string>() : new Map([[`${x},${y}`, 'move']]); }
        return abilityTargetMode
            ? new Map([...abilityTargets(cap).keys()].map(key => [key, 'ability']))
            : new Map([...moveTargets(cap)].map(([key, target]) => [key, target.type]));
    });

    function cellFromPoint(px: number, py: number): { x: number; y: number } | null {
        if (boardMode === '3d') return boardPicker?.(px,py) ?? null;
        const el = document.elementFromPoint(px, py);
        const cell = el?.closest('[data-cell]') as HTMLElement | null;
        if (!cell) return null;
        const [x, y] = (cell.dataset.cell ?? '').split(',').map(Number);
        if (Number.isNaN(x) || Number.isNaN(y)) return null;
        return { x, y };
    }

    function benchCapFromPoint(px: number, py: number): number | null {
        const el = document.elementFromPoint(px, py);
        const bp = el?.closest('[data-bench]') as HTMLElement | null;
        if (!bp) return null;
        const id = Number(bp.dataset.bench);
        return Number.isNaN(id) ? null : id;
    }

    function vibrate(ms: number) {
        try { navigator.vibrate?.(ms); } catch { /* not supported */ }
    }

    function capDefFor(c: ChainCap): CapTypeDef | undefined {
        return capDefMap.get(c.capType);
    }

    function abilityTargets(cap: ChainCap): Map<string, { targetType: number }> {
        const out = new Map<string, { targetType: number }>();
        const def = capDefFor(cap);
        if (!def || def.abilityTarget === 0) return out;
        if (cap.x === null || cap.y === null) return out;
        if (!game || remainingEnergy < def.abilityCost) return out;
        for (let x = 0; x < activeLayout.width; x++) for (let y = 0; y < activeLayout.height; y++) {
            if (pathDistance(activeLayout, [cap.x, cap.y], [x, y]) > Math.min(65535, def.abilityRange + passiveBonus('AbilityRangeBonus', cap, simCaps, capDefMap, activeLayout))) continue;
            if (!activeLayout.isWalkable(x, y)) continue;
            const occ = capAt(x, y);
            switch (def.abilityTarget) {
                case 2: if (occ && isMyCap(occ)) out.set(`${x},${y}`, { targetType: 2 }); break;
                case 3: if (occ && !isMyCap(occ)) out.set(`${x},${y}`, { targetType: 3 }); break;
                case 4: if (occ) out.set(`${x},${y}`, { targetType: 4 }); break;
                case 5: out.set(`${x},${y}`, { targetType: 5 }); break;
            }
        }
        return out;
    }

    function abilityTargetModeStart() {
        if (selectedCapId == null) return;
        const cap = capById(selectedCapId);
        if (!cap) return;
        const def = capDefFor(cap);
        if (!def || def.abilityTarget === 0 || !canActivateSelected) return;
        if (def.abilityTarget >= 6) { stackTargetMode = true; abilityTargetMode = false; overlay = 'stack'; return; }
        if (def.abilityTarget === 1) {
            if (queueAction(cap.id, 'Ability', cap.x ?? 0, cap.y ?? 0)) {
                status = `Queued ability: ${def.abilityDescription}`;
                selectedCapId = null;
            }
            return;
        }
        abilityTargetMode = true;
    }

    function capAt(x: number, y: number): ChainCap | undefined {
        return simCaps.find(c => c.x === x && c.y === y) ?? undefined;
    }

    function capById(id: number): ChainCap | undefined {
        return simCaps.find(c => c.id === id) ?? undefined;
    }

    function turnPlayerAddress(): string | null {
        if (!game) return null;
        return game.turnCount % 2 === 0 ? game.player1 : game.player2;
    }

    function isMyCap(c: ChainCap): boolean {
        if (!account || !game) return false;
        return c.playerSlot === mySlot;
    }

    function isMyTurn(): boolean {
        if (!game || !account) return false;
        return BigInt(turnPlayerAddress()!) === BigInt(account);
    }

    function canAct(): boolean {
        return !!game && !game.over && isMyTurn() && !committing && !pendingForGame && busy === null;
    }

    function benchCaps(): ChainCap[] {
        return simCaps.filter(c => c.x === null && !c.dead);
    }

    function myBenchCaps(): ChainCap[] {
        if (mySlot === null || !game) return [];
        const ids = new Set(isMyTurn() ? preview?.hand : opponentHand?.window);
        return benchCaps().filter(c => c.playerSlot === mySlot && ids.has(c.id));
    }

    /** Bench pieces waiting for the hand cycle to come around. */
    function lockedBenchCount(): number {
        if (mySlot === null) return 0;
        const all = benchCaps().filter(c => c.playerSlot === mySlot);
        return all.length - myBenchCaps().length;
    }

    function isDeploySpot(x: number, y: number): boolean {
        if (!game) return false;
        const [dx, dy] = game.turnCount % 2 === 0 ? activeLayout.p1Deploy : activeLayout.p2Deploy;
        return x === dx && y === dy;
    }

    function deploySpot(): [number, number] {
        return game!.turnCount % 2 === 0 ? activeLayout.p1Deploy : activeLayout.p2Deploy;
    }

    /** For a cap on the board: legal 1-step targets (empty moves + enemy contacts). */
    function moveTargets(cap: ChainCap): Map<string, { type: 'move' | 'fight'; dmg?: number }> {
        const out = new Map<string, { type: 'move' | 'fight'; dmg?: number }>();
        if (!canAct() || !isMyCap(cap) || cap.stunnedTurns > 0 || abilityTargetMode || (preview?.actions ?? 0) + (preview?.moves ?? 0) === 0) return out;
        if (cap.x === null || cap.y === null) return out;
        const dmg = capDefFor(cap)?.attack ?? 0;
        for (const [x, y] of activeLayout.neighbors([cap.x, cap.y])) {
            const occ = capAt(x, y);
            if (!occ) out.set(`${x},${y}`, { type: 'move' });
            else if (!isMyCap(occ)) out.set(`${x},${y}`, { type: 'fight', dmg: Math.max(0, dmg + passiveBonus('AttackBonus', cap, simCaps, capDefMap, activeLayout) - passiveBonus('DamageReduction', occ, simCaps, capDefMap, activeLayout)) });
        }
        return out;
    }

    function queueAction(capId: number, kind: Exclude<TurnAction['kind'], 'StackAbility'>, x: number, y: number): boolean {
        if (!game || !canAct()) return false;
        const next = [...queuedActions, { capId, kind, x, y }];
        try {
            previewTurn(game, hand, capDefMap, activeLayout, next, pendingStack);
            queuedActions = next;
            status = `Queued ${kind} → (${x},${y})`;
            errorMsg = null;
            vibrate(15);
            return true;
        } catch (e) {
            errorMsg = e instanceof Error ? e.message : String(e);
            return false;
        }
    }

    function tryDeploy(capId: number): boolean {
        const [dx, dy] = deploySpot();
        if (capAt(dx, dy)) {
            errorMsg = 'Deploy spot is occupied';
            log('Deploy spot occupied', 'error');
            return false;
        }
        return queueAction(capId, 'Play', dx, dy);
    }

    function tryMove(capId: number, x: number, y: number): boolean {
        const cap = capById(capId);
        if (!cap || cap.x === null || cap.y === null) return false;
        const targets = moveTargets(cap);
        const t = targets.get(`${x},${y}`);
        if (!t) return false;
        return queueAction(capId, 'Move', x, y);
    }

    // Tap resolution
    function onTapCell(x: number, y: number) {
        hoveredCapId = null;
        if (!activeLayout.isWalkable(x, y)) return;
        stackTargetMode = false;
        const occ = capAt(x, y);
        if (!canAct()) { selectedCapId = occ?.id ?? null; abilityTargetMode = false; return; }

        // ability targeting
        if (abilityTargetMode && selectedCapId != null) {
            const cap = capById(selectedCapId);
            if (cap) {
                const targets = abilityTargets(cap);
                if (targets.has(`${x},${y}`)) {
                    if (queueAction(selectedCapId, 'Ability', x, y)) {
                        abilityTargetMode = false;
                        selectedCapId = null;
                        return;
                    }
                }
            }
            abilityTargetMode = false;
        }

        if (occ && isMyCap(occ)) {
            selectedCapId = selectedCapId === occ.id ? null : occ.id;
            return;
        }

        if (selectedCapId != null && selectedActor?.x === null && isDeploySpot(x,y)) { if (tryDeploy(selectedCapId)) selectedCapId = null; return; }
        if (selectedCapId != null) {
            if (tryMove(selectedCapId, x, y)) {
                // keep selection? deselect for clarity
                selectedCapId = null;
                return;
            }
        }

        // Inspect an enemy when no legal action was selected.
        selectedCapId = occ?.id ?? null;
    }

    function onTapBench(capId: number) {
        selectedCapId = selectedCapId === capId ? null : capId;
        hoveredCapId = null; abilityTargetMode = false;
    }

    // Pointer engine: unified tap + drag for board & bench
    interface DragState {
        capId: number;
        fromBench: boolean;
        capType: number;
        owner: string;
        px: number;
        py: number;
        over: { x: number; y: number } | null;
        valid: boolean;
        label: string | null;
    }
    let drag: DragState | null = $state(null);
    let downInfo: {
        px: number; py: number;
        capId?: number; fromBench?: boolean; capType?: number; owner?: string;
        cell?: { x: number; y: number };
    } | null = $state(null);

    function beginDragIfCap(px: number, py: number) {
        const d = downInfo!;
        if (d.capId === undefined) return;
        const cap = capById(d.capId);
        if (!cap || !canAct() || !isMyCap(cap) || cap.stunnedTurns || abilityTargetMode) return;
        hoveredCapId = null;
        // validate drop targets so ghost shows legal cells
        drag = {
            capId: d.capId,
            fromBench: !!d.fromBench,
            capType: cap.capType,
            owner: cap.owner,
            px, py,
            over: null,
            valid: false,
            label: null,
        };
    }

    function evaluateDragTarget(px: number, py: number) {
        if (!drag) return;
        const over = cellFromPoint(px, py);
        drag.px = px;
        drag.py = py;
        drag.over = over;
        drag.valid = false;
        drag.label = null;
        if (!over || !canAct()) return;
        if (drag.fromBench) {
            drag.valid = (preview?.actions ?? 0) > 0 && !capAt(over.x, over.y) && isDeploySpot(over.x, over.y);
        } else {
            const cap = capById(drag.capId);
            if (!cap) return;
            const t = moveTargets(cap).get(`${over.x},${over.y}`);
            if (t) {
                drag.valid = true;
                drag.label = t.type === 'fight' ? `\u2694\ufe0f ${t.dmg}` : null;
            }
        }
    }

    function finishDrag(commit: boolean) {
        if (!drag) return;
        const { capId, fromBench, over, valid } = drag;
        drag = null;
        downInfo = null;
        if (!commit || !over || !valid) return;
        if (fromBench) {
            if (tryDeploy(capId)) selectedCapId = null;
        } else {
            tryMove(capId, over.x, over.y);
            selectedCapId = null;
        }
    }

    function onPointerDown(e: PointerEvent) {
        if (!game || committing || busy !== null || overlay || !e.isPrimary || activePointer !== null) return;
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        const px = e.clientX, py = e.clientY;

        const benchId = benchCapFromPoint(px, py);
        if (benchId !== null) {
            downInfo = { px, py, capId: benchId, fromBench: true };
            activePointer = e.pointerId; pointerElement = e.currentTarget as HTMLElement;
            pointerElement.setPointerCapture(e.pointerId);
            return;
        }
        const cell = cellFromPoint(px, py);
        if (cell) {
            const occ = capAt(cell.x, cell.y);
            if (occ && isMyCap(occ) && canAct()) {
                downInfo = { px, py, capId: occ.id, fromBench: false, cell };
            } else {
                downInfo = { px, py, cell };
            }
            activePointer = e.pointerId; pointerElement = e.currentTarget as HTMLElement;
            pointerElement.setPointerCapture(e.pointerId);
        }
    }

    function onPointerMove(e: PointerEvent) {
        if (!downInfo || e.pointerId !== activePointer) return;
        const dist = Math.hypot(e.clientX - downInfo.px, e.clientY - downInfo.py);
        if (!drag && dist > 8 && downInfo.capId !== undefined) {
            beginDragIfCap(e.clientX, e.clientY);
        }
        if (drag) evaluateDragTarget(e.clientX, e.clientY);
    }

    function onPointerUp(e: PointerEvent) {
        if (e.pointerId !== activePointer) return;
        try {
        if (drag) {
            evaluateDragTarget(e.clientX, e.clientY);
            finishDrag(true);
            return;
        }
        if (!downInfo) return;
        const dist = Math.hypot(e.clientX - downInfo.px, e.clientY - downInfo.py);
        const upCell = cellFromPoint(e.clientX, e.clientY);
        const upBench = benchCapFromPoint(e.clientX, e.clientY);
        if (dist <= 8 && downInfo.capId !== undefined && downInfo.fromBench) {
            // A tap inspects; only a valid drag drop deploys.
            onTapBench(downInfo.capId);
        } else if (dist <= 8 && downInfo.cell && upCell &&
                   upCell.x === downInfo.cell.x && upCell.y === downInfo.cell.y) {
            onTapCell(upCell.x, upCell.y);
        } else if (dist <= 8 && upBench !== null && downInfo.capId === upBench) {
            onTapBench(upBench);
        }
        downInfo = null;
        } finally { onPointerCancel(); }
    }

    function onPointerCancel() {
        const id = activePointer, element = pointerElement; activePointer = null; pointerElement = null;
        if (id !== null && element?.hasPointerCapture(id)) element.releasePointerCapture(id);
        drag = null;
        downInfo = null;
    }

    // Lobby / connection flows (unchanged behavior)
    async function handleConnect() {
        errorMsg = null;
        busy = isDevMode() ? 'Connecting test account…' : 'Opening Controller…';
        log('Connect requested');
        try {
            const acc = await connect();
            account = acc.address;
            status = 'Connected';
            log(`Connected as ${acc.address.slice(0, 10)}…`);
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Connect failed: ${errorMsg}`, 'error');
        } finally {
            busy = null;
        }
    }

    async function handleCreateSolo() { await createAndLoad(); }
    async function handleCreate() {
        const opponentAddress = opponent.trim();
        if (!opponentAddress) { errorMsg = 'Enter an opponent address'; return; }
        await createAndLoad(opponentAddress);
    }

    async function createAndLoad(opponentAddress?: string) {
        errorMsg = null;
        if (!account) { errorMsg = 'Connect first'; return; }
        busy = 'Creating game…';
        try {
            if (opponentAddress) await createGame(opponentAddress, selectedLayout);
            else await createSoloGame(selectedLayout);
            busy = 'Finding your game…';
            const id = await findLatestGameForPlayer(account);
            if (id === null) {
                status = 'Game created — enter its id manually to load';
                return;
            }
            gameIdInput = String(id);
            await loadGame(id);
        } catch (e: unknown) {
            errorMsg = e instanceof Error ? e.message : String(e);
            log(`Create failed: ${errorMsg}`, 'error');
        } finally {
            busy = null;
        }
    }

    async function handleLoad() {
        if (busy || committing) return;
        busy = 'Refreshing game…';
        try { await loadGame(Number(gameIdInput)); } finally { busy = null; }
    }

    async function loadGame(id: number, stillCurrent: () => boolean = () => true, minimumTurn = 0) {
        const epoch = ++loadEpoch;
        try {
            if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Enter a valid game id');
            const snapshot = await deadline(getGameSnapshot(id, minimumTurn));
            if (epoch !== loadEpoch || !stillCurrent()) return false;
            const nextGame = snapshot.game;
            if (game?.id === id && pendingForGame && nextGame.turnCount <= pendingForGame.turn) {
                syncStage = pendingForGame.confirmed ? 'syncing' : 'confirming';
                return false;
            }
            onPointerCancel();
            queuedActions = []; selectedCapId = null; hoveredCapId = null; abilityTargetMode = false; stackTargetMode = false;
            capDefMap = snapshot.definitions; pendingStack = snapshot.stack;
            hand = snapshot.hand; opponentHand = snapshot.otherHand; clockSample = snapshot.clock; game = nextGame;
            if (submissionHasLanded(pendingForGame, game.turnCount)) {
                pendingSubmission = null; syncStage = 'idle'; submissionEpoch++;
            }
            /* Loading an old match must not replace the new-game map preference. */ resumeId = id; gameIdInput = String(id); linkCopied = false;
            lastSynced = new Date().toLocaleTimeString(); syncError = null; errorMsg = null;
            if (!pendingStack.entries.some(e => e.id === focusedEffectId)) focusedEffectId = null;
            try {
                localStorage.setItem(savedGameKey, String(id));
                const url = new URL(location.href); url.searchParams.set('game', String(id));
                history.replaceState(history.state, '', url);
            } catch { /* Browser storage is optional. */ }
            status = `Loaded game #${id}`;
            void loadHistory(id, game.turnCount);
            return true;
        } catch (error) {
            if (epoch !== loadEpoch || !stillCurrent()) return false;
            syncError = error instanceof Error ? error.message : String(error);
            if (!game) errorMsg = syncError;
            log(`Load: ${syncError}`, 'error');
            return false;
        }
    }

    // Keep checking both sides: another tab may submit, and receipts can precede RPC state.
    $effect(() => {
        const id = game?.id;
        if (!id) return;
        let cancelled = false, checking = false;
        const current = () => !cancelled && game?.id === id;
        async function check() {
            if (checking || !current() || committing || busy) return;
            checking = true;
            try {
                const pending = pendingSubmission?.gameId === id ? pendingSubmission : null;
                if (pending) {
                    const receipt = await deadline(transactionState(pending.hash));
                    if (!current()) return;
                    if (receipt === 'reverted') {
                        pendingSubmission = null; syncStage = 'idle'; submissionEpoch++;
                        errorMsg = 'The transaction reverted. Your plan is still here; refresh before trying again.';
                    } else if (receipt === 'confirmed') {
                        pendingSubmission = {...pending, confirmed:true}; syncStage = 'syncing';
                        await loadGame(id!, current, pending.turn + 1);
                    }
                } else {
                    const [next, sample] = await deadline(Promise.all([getGame(id!), getClock(id!)]));
                    if (!current()) return;
                    // A clock read can cross a turn boundary too. Reload all state if its
                    // stored banks differ; otherwise only refresh the chain-time anchor.
                    const oldClock = clockSample?.clock;
                    const clockChanged = !oldClock || (['enabled', 'p1Seconds', 'p2Seconds', 'runningSince', 'timedOutSlot'] as const)
                        .some(key => oldClock[key] !== sample.clock[key]);
                    if (next && (next.turnCount !== game?.turnCount || next.over !== game?.over || clockChanged)) await loadGame(id!, current);
                    else { clockSample = sample; lastSynced = new Date().toLocaleTimeString(); syncError = null; }
                }
            } catch (error) { if (current()) syncError = error instanceof Error ? error.message : String(error); }
            finally { checking = false; }
        }
        const timer = setInterval(check, 5000);
        const visible = () => { if (document.visibilityState === 'visible') void check(); };
        document.addEventListener('visibilitychange', visible);
        return () => { cancelled = true; clearInterval(timer); document.removeEventListener('visibilitychange', visible); };
    });

    async function commitTurn(claim = false) {
        if (!game || (claim ? !canClaimTimeout : !canAct())) return;
        const id = game.id, turn = game.turnCount, attempt = ++submissionEpoch;
        errorMsg = null; syncError = null; committing = true; syncStage = 'submitting';
        try {
            const progress: TransactionProgress = (stage, hash) => {
                if (attempt !== submissionEpoch) return;
                pendingSubmission = {gameId:id,turn,hash,confirmed:stage === 'syncing'};
                syncStage = stage;
            };
            await deadline(claim ? claimTimeout(id, turn, progress) : takeTurn(id, turn, queuedActions, progress), 45000);
            await loadGame(id, () => game?.id === id, turn + 1);
        } catch (error) {
            syncError = error instanceof Error ? error.message : String(error);
            if (!pendingSubmission) { errorMsg = syncError; syncStage = 'idle'; }
        } finally { committing = false; }
    }

    function removeQueuedAction(index: number) {
        // Later actions may depend on this move, deployment, or ability grant.
        queuedActions = queuedActions.slice(0, index);
    }

    function pct(pos: number, size: number): string {
        return `${((pos + 0.5) / size) * 100}%`;
    }

</script>

<svelte:window onblur={onPointerCancel} />

<svelte:head>
    <title>CAPS — Onchain Strategy Game</title>
    <meta name="description" content="Play CAPS, a tactical onchain board game on Starknet." />
    <meta name="theme-color" content="#0f172a" />
</svelte:head>

<div class="wrap" class:playing={!!game}>
    {#if !game}<header class="topbar">
        <h1>CAPS</h1>
        {#if account}
            {#if devMode}<span class="dev-badge">SEPOLIA TEST</span>{/if}
            <button class="addr" onclick={copyAddress} title="Tap to copy full address">
                {addrCopied ? '✓ Copied' : `${account.slice(0, 6)}…${account.slice(-4)}`}
                <span class="copy-icon">{addrCopied ? '' : '⧉'}</span>
            </button>
        {/if}
    </header>{/if}

    {#if !game}
        <section class="lobby" aria-label="Play CAPS">
            <div class="lobby-intro"><span class="eyebrow">TACTICAL BOARD GAME</span><h2>Find your path.<br />Reach their goal.</h2><p>Build your position, time your abilities, and break through.</p><span class="format-chip">◷ 2 min + 10 sec / turn</span></div>
            {#if errorMsg}<div class="error" role="alert">{errorMsg}</div>{/if}
            {#if busy}<div class="busy" role="status"><span class="spinner"></span>{busy}</div>{/if}
            {#if !account}
                <button class="primary big" onclick={handleConnect} disabled={busy !== null}>{devMode ? 'Start playing' : 'Connect Controller'}</button>
                {#if devMode}<p class="hint">Sepolia playtest · shared test account</p>{/if}
            {:else}
                {#if resumeId}<button class="resume-game" onclick={() => { gameIdInput = String(resumeId); void handleLoad(); }} disabled={busy !== null}><span>Continue game <b>#{resumeId}</b></span><span>↗</span></button>{/if}
                <section class="menu-card new-match" aria-label="New match">
                    <div class="field"><label for="layout-select">Your battlefield</label><select id="layout-select" bind:value={selectedLayout} disabled={busy !== null}>{#each Object.values(LAYOUTS) as l}<option value={l.id}>{l.name}</option>{/each}</select><p class="hint">{getLayout(selectedLayout).description}</p></div>
                    <button class="primary big play-bot" onclick={() => createAndLoad(botAccount.address)} disabled={busy !== null}><span>Play the bot<small>A quick tactical challenge</small></span><span aria-hidden="true">→</span></button>
                    <button class="solo-button" onclick={handleCreateSolo} disabled={busy !== null}>Practice · control both sides</button>
                    <p class="hint">The clock starts when the match is created. The bot checks for turns about every 15 seconds.</p>
                </section>
                <details class="menu-card"><summary>Challenge a friend <span>＋</span></summary><div class="menu-content"><p class="hint">Enter their account address, then share the game link.</p><div class="field"><label for="opp">Opponent address</label><input id="opp" bind:value={opponent} placeholder="0x…" autocomplete="off" spellcheck="false" /></div><button onclick={handleCreate} disabled={!opponent.trim() || busy !== null}>Create challenge →</button></div></details>
                <details class="menu-card"><summary>Open a game <span>↗</span></summary><div class="menu-content"><div class="field"><label for="game-id">Game number</label><div class="field row"><input id="game-id" bind:value={gameIdInput} type="number" min="1" inputmode="numeric" placeholder="Game number" /><button onclick={handleLoad} disabled={busy !== null}>Open</button></div></div></div></details>
                <details class="menu-card"><summary>Account & connection <span>⌁</span></summary><div class="menu-content"><p class="hint">{status} · Sepolia{devMode ? ' · shared test account' : ''}</p><button onclick={copyAddress}>{addrCopied ? 'Address copied' : 'Copy account address'}</button><p class="hint">If a transaction needs gas, add free Sepolia STRK to this address and retry.</p><a class="faucet-link" href="https://starknet-faucet.vercel.app/" target="_blank" rel="noopener noreferrer">Get test STRK ↗</a></div></details>
            {/if}
        </section>
    {:else}
        <section class="play-screen" aria-label="CAPS game">
            <div class="play-top"><header class="play-hud">
                <button aria-label="Game menu" onclick={() => overlay = 'menu'}>☰</button>
                <span class="turn-indicator" class:your-turn={isMyTurn()}>{isSolo ? `P${game.turnCount % 2 + 1}` : isMyTurn() ? 'Your turn' : 'Opponent'} <small>· {game.turnCount + 1}</small></span>
                <span class="hud-energy" title="Your energy">⚡ {isMyTurn() ? remainingEnergy : mySlot === 0 ? game.p1Energy : game.p2Energy}</span>
                <button class:has-effects={!!preview?.stack.entries.length} aria-label={`Ability stack: ${preview?.stack.entries.length ?? 0} effects`} onclick={() => overlay = 'stack'}>◷ {preview?.stack.entries.length ?? 0}</button>
                <button aria-label="Opponent moves and turn history" onclick={() => overlay = 'history'}>↶</button>
            </header>
            <div class="clock-strip" aria-label="Game clocks: two minutes plus ten seconds per turn">
                {#each [mySlot ?? 0, 1 - (mySlot ?? 0)] as slot}
                    <span class:running={!game.over && game.turnCount % 2 === slot} class:low={clockTimes !== null && clockTimes[slot] < 20}>
                        <small>{isSolo || mySlot === null ? `P${slot + 1}` : slot === mySlot ? 'You' : 'Opponent'}</small>
                        <b aria-label={`${isSolo ? `Player ${slot + 1}` : slot === mySlot ? 'Your' : 'Opponent'} time ${clockLabel(clockTimes?.[slot])}`}>{clockLabel(clockTimes?.[slot])}</b>
                    </span>
                {/each}
            </div></div>
            <div class="play-stage">
                {#if boardMode === '3d'}
                    <svelte:boundary onerror={fallbackBoard}>
                        {#if ThreeBoard}
                            <ThreeBoard viewer={mySlot} layout={activeLayout} caps={simCaps} definitions={capDefMap} selectedId={drag?.capId ?? selectedCapId} targets={sceneTargets} {focusedCells} stack={preview?.stack ?? pendingStack} onpickready={(pick) => boardPicker = pick} onpointerdown={onPointerDown} onpointermove={onPointerMove} onpointerup={onPointerUp} onpointercancel={onPointerCancel} onhover={(id) => { if (!drag) hoveredCapId = id; }} onfailure={fallbackBoard} />
                        {:else}<p class="stage-notice" role="status">Loading board…</p>{/if}
                    </svelte:boundary>
                {:else}
            <!-- Board: static tiles + gliding pieces layer -->
            <div
                class="board" class:routed={!!activeLayout.connections?.length} class:flipped={mySlot === 0}
                role="application"
                aria-label="Game board"
                style="--w:{activeLayout.width};--h:{activeLayout.height}"
                onpointerdown={onPointerDown}
                onpointermove={onPointerMove}
                onpointerup={onPointerUp}
                onpointercancel={onPointerCancel}
                onlostpointercapture={onPointerCancel}
            >
                {#each Array.from({ length: activeLayout.height * activeLayout.width }, (_, idx) => idx) as idx}
                    {@const x = idx % activeLayout.width}
                    {@const y = Math.floor(idx / activeLayout.width)}
                    {@const walkable = activeLayout.isWalkable(x, y)}
                    {@const isDeploy = isDeploySpot(x, y)}
                    {@const occ = capAt(x, y)}
                    {@const selCap = capById(drag?.capId ?? selectedCapId ?? -1)}
                    {@const selTargets = selCap && selCap.x !== null && selCap.y !== null ? moveTargets(selCap) : null}
                    {@const targetInfo = selTargets?.get(`${x},${y}`)}

                    {@const isAbilityTgt = selectedCapId != null && abilityTargetMode
                        && (() => {
                            const cap = capById(selectedCapId);
                            if (!cap) return false;
                            return abilityTargets(cap).has(`${x},${y}`);
                        })()}
                    {@const dragOver = drag?.over?.x === x && drag?.over?.y === y}
                    <div
                        class="tile"
                        class:void-tile={!walkable}
                        class:connector-tile={connectorCells.has(`${x},${y}`)}
                        class:goal-tile={goalSlot(activeLayout,x,y) !== null}
                        class:energy-tile={isEnergySpace(activeLayout,x,y)}
                        class:deploy-tile={isDeploy && !occ}
                        class:effect-focus={focusedCells.has(`${x},${y}`)}
                        class:pending-danger={walkable && !!preview?.stack.entries.some(e => e.impact.kind === 'Damage' && e.impact.selection.kind === 'Row' && e.impact.selection.index === y)}
                        class:target-move={!!targetInfo && targetInfo.type === 'move'}
                        class:target-fight={!!targetInfo && targetInfo.type === 'fight'}
                        class:target-ability={isAbilityTgt}
                        class:drag-over={dragOver}
                        class:drag-ok={dragOver && drag?.valid}
                        class:drag-bad={dragOver && drag != null && !drag.valid}
                        title={square(x,y)}
                        data-cell="{x},{y}"
                    >
                        {#if walkable}<span class="coordinate">{square(x,y)}</span>{/if}
                        {#if goalSlot(activeLayout,x,y) !== null}
                            <div class="goal-marker">P{goalSlot(activeLayout,x,y)! + 1} base</div>
                        {:else if isEnergySpace(activeLayout,x,y)}
                            <div class="deploy-marker">⚡</div>
                        {:else if !walkable && !activeLayout.connections?.length}
                            <div class="void-marker">·</div>
                        {/if}
                        {#if targetInfo && targetInfo.type === 'fight'}
                            <div class="fight-badge">⚔ {targetInfo.dmg}</div>
                        {/if}
                        {#if dragOver}
                            <div class="drag-ring"></div>
                        {/if}
                    </div>
                {/each}

                <svg class="paths" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
                    {#each pathEdges(activeLayout) as edge}
                        <line x1={(edge.x1 + 0.5) / activeLayout.width * 100} y1={(edge.y1 + 0.5) / activeLayout.height * 100} x2={(edge.x2 + 0.5) / activeLayout.width * 100} y2={(edge.y2 + 0.5) / activeLayout.height * 100} />
                    {/each}
                </svg>
                <!-- Pieces: absolutely positioned, glide between tiles -->
                <div class="pieces-layer">
                    {#each simCaps as c (c.id)}
                        {#if c.x !== null && c.y !== null}
                            {@const isDragging = drag?.capId === c.id}
                            <div
                                class="piece p{c.playerSlot + 1}"
                                class:selected={selectedCapId === c.id}
                                class:drag-origin={isDragging}
                                class:my-piece={isMyCap(c)}
                                style="left:{pct(c.x, activeLayout.width)};top:{pct(c.y, activeLayout.height)}"
                            >
                                <div class="piece-body">
                                    <div class="type" title={capDefFor(c)?.name}>{(capDefFor(c)?.name ?? String(c.capType)).slice(0, 3)}</div>
                                    <div class="hp">{c.health}</div>
                                    {#if c.shield > 0}<div class="shield-badge">🛡{c.shield}</div>{/if}
                                    {#if c.stunnedTurns > 0}<div class="stun-badge">💫</div>{/if}
                                    {#if capDefFor(c) && capDefFor(c)!.passives.length > 0}
                                        <div class="passive-badge">✦</div>
                                    {/if}
                                </div>
                            </div>
                        {/if}
                    {/each}
                </div>
            </div>

                {/if}
                {#if preview?.stack.entries.length}
                    <button class="stack-chip" onclick={() => overlay = 'stack'}>◷ {effectTiming(preview.stack.entries.at(-1)!, preview.stack, game.turnCount, mySlot)}</button>
                {/if}
                {#if abilityTargetMode}<button class="target-prompt" onclick={() => abilityTargetMode = false}>Choose a glowing target · Cancel ✕</button>{/if}
                {#if focusedEffectId !== null}<button class="target-prompt" onclick={() => focusedEffectId = null}>Effect #{focusedEffectId} highlighted · Clear ✕</button>{/if}
                {#if game.over}
                    <div class="end-card"><h2>{isSolo ? `P${game.winnerSlot + 1} wins` : game.winnerSlot === mySlot ? 'You win' : 'Opponent wins'}</h2><p>{timedOut ? 'Won on time' : 'Goal reached'}</p><button onclick={() => createAndLoad(isSolo ? undefined : mySlot === 0 ? game!.player2 : game!.player1)} disabled={busy !== null}>Play again</button></div>
                {/if}

            </div>
            {#if drag}<div class="drag-preview" class:legal={drag.valid} style:left={`${drag.px}px`} style:top={`${drag.py}px`}><b>{pieceSymbol(drag.capType)}</b><span>{drag.valid ? drag.fromBench ? 'Deploy' : drag.label ? 'Attack' : 'Move' : 'Release to cancel'}</span></div>{/if}
            <footer class="play-dock">
                {#if inspectedActor && !abilityTargetMode && !overlay}
                    {@const selectedActor = inspectedActor}
                    {@const def = capDefFor(selectedActor)}
                    {#if def}
                    <section class="selection-card" class:hover-only={selectedCapId === null} aria-label="Selected piece">
                        <div class="selection-title"><strong>{pieceSymbol(selectedActor.capType)} {def.name}</strong><span>♥ {selectedActor.health} · ⚔ {def.attack + passiveBonus('AttackBonus', selectedActor, simCaps, capDefMap, activeLayout)}{selectedActor.shield ? ` · ⛨ ${selectedActor.shield}` : ''}</span><button aria-label="Deselect piece" onclick={() => { selectedCapId = null; hoveredCapId = null; abilityTargetMode = false; }}>✕</button></div>
                        {#if def.abilityTarget}<p>{def.abilityDescription}</p>{/if}
                        {#each def.passives as passive}<p class="passive-description">{passiveLabel(passive)} · {passiveActive(passive, selectedActor, def.maxHealth, simCaps, activeLayout) ? 'Active' : 'Inactive'}</p>{/each}
                        {#if selectedActor.stunnedTurns}<p>Stunned · {selectedActor.stunnedTurns}</p>{/if}
                        {#if selectedActor.x === null && isMyCap(selectedActor)}
                            <button class="selection-action" disabled={!canAct() || (preview?.actions ?? 0) === 0 || !myBenchCaps().some(c => c.id === selectedCapId)} onclick={() => { if (tryDeploy(selectedActor!.id)) selectedCapId = null; }}>Deploy</button>
                        {:else if def.abilityTarget && isMyCap(selectedActor)}
                            <button class="selection-action" disabled={!canActivateSelected} onclick={abilityTargetModeStart}>Activate · ⚡ {def.abilityCost}</button>
                        {/if}
                    </section>
                    {/if}
                {/if}
                <div class="hand-strip" aria-label="Your hand">
                    {#each myBenchCaps() as c (c.id)}
                        <button class:selected={selectedCapId === c.id} aria-pressed={selectedCapId === c.id} data-bench={c.id} onpointerdown={onPointerDown} onpointermove={onPointerMove} onpointerup={onPointerUp} onpointercancel={onPointerCancel} onlostpointercapture={onPointerCancel} onpointerenter={(event) => { if (event.pointerType === 'mouse') hoveredCapId = c.id; }} onpointerleave={() => hoveredCapId = null} aria-label={`Select ${capDefFor(c)?.name ?? 'piece'}, ${c.health} health`} onclick={(event) => { if (event.detail === 0) onTapBench(c.id); }}><b>{pieceSymbol(c.capType)}</b><span>{capDefFor(c)?.name ?? c.capType}</span></button>
                    {/each}
                    {#if !myBenchCaps().length}<span class="empty-hand">No pieces in hand</span>{/if}
                </div>
                <div class="turn-controls">
                    <button aria-label="Undo last planned action" disabled={!canAct() || !queuedActions.length} onclick={() => removeQueuedAction(queuedActions.length - 1)}>↶</button>
                    <span class="action-dots" aria-label={`${preview?.actions ?? 1} normal actions and ${preview?.moves ?? 0} bonus moves remaining`}>{(preview?.actions ?? 1) ? '●' : '○'}{(preview?.moves ?? 0) > 0 ? ` +${preview?.moves}` : ''}</span>
                    <button class="submit-turn" onclick={() => commitTurn(canClaimTimeout)} disabled={!canAct() && !canClaimTimeout}>{syncStage === 'submitting' ? 'Sending…' : syncStage === 'confirming' ? 'Confirming…' : syncStage === 'syncing' ? 'Updating…' : game.over ? 'Game over' : canClaimTimeout ? 'Claim timeout win →' : !isMyTurn() ? 'Opponent’s turn' : queuedActions.length ? 'End turn →' : 'Pass →'}</button>
                </div>
                <div class="connection-line" role="status" aria-live="polite">{errorMsg ?? syncError ?? (busy || (syncStage === 'idle' ? queuedActions.length ? 'Plan ready' : ' ' : 'Waiting for the network…'))}</div>
            </footer>
            <dialog class="game-sheet" bind:this={sheet} onclose={closeOverlay} oncancel={closeOverlay}>
                <header><strong>{overlay === 'stack' ? 'Pending abilities' : overlay === 'history' ? 'Last moves' : `Game #${game.id}`}</strong><button aria-label="Close panel" onclick={closeOverlay}>✕</button></header>
                <div class="sheet-body">
                    {#if overlay === 'stack'}
                        <StackPanel stack={preview?.stack ?? pendingStack} confirmedId={pendingStack.nextId} turn={game.turnCount} viewer={mySlot} caps={simCaps} definitions={capDefMap} layout={activeLayout} actor={selectedActor} targeting={stackTargetMode} canActivate={canActivateSelected} focusedId={focusedEffectId} onfocus={(id) => { focusedEffectId = id; closeOverlay(); }} ontarget={targetPending} oncancel={closeOverlay} />
                    {:else if overlay === 'history'}
                        {#if timedOut}<p class="timeout-result">P{clockSample!.clock.timedOutSlot + 1} ran out of time. P{game.winnerSlot + 1} wins.</p>{/if}
            {#if latestOpponent}
                <section class="opponent-last" aria-label="Opponent’s last turn">
                    <strong>{isSolo ? `P${latestOpponent.playerSlot + 1}` : 'Opponent'} · turn {latestOpponent.turn + 1}</strong>
                    {#if !latestOpponent.actions.length}<p>Passed without taking an action.</p>{/if}
                    {#each latestOpponent.actions as action}<p>{actionLabel(action, latestOpponent.before, capDefMap)}</p>{/each}

                </section>
            {/if}


                        <TurnHistory records={historyRecords} definitions={capDefMap} viewer={mySlot} loading={historyLoading} error={historyError} hasOlder={historyCursor > 0} onolder={() => { void loadHistory(game?.id, game?.turnCount, true); }} />
                    {:else if overlay === 'menu'}
                        <div class="match-summary"><span class="eyebrow">{isSolo ? 'PRACTICE' : 'HEAD TO HEAD'}</span><h2>{activeLayout.name}</h2><p>Turn {game.turnCount + 1} · 2 min + 10 sec / turn</p></div>
                        <button class="primary" onclick={closeOverlay}>Back to board →</button>
                        <div class="menu-actions"><button onclick={copyGameLink}>{linkCopied ? 'Link copied ✓' : 'Share game ↗'}</button><button onclick={handleLoad} disabled={committing || busy !== null}>Refresh ↻</button></div>
                        {#if errorMsg || syncError}<p role="alert">{errorMsg ?? syncError}</p>{/if}
                        <section class="menu-card display-settings" aria-label="Board display"><span>Board view</span><div class="segmented"><button aria-pressed={boardMode === '3d'} onclick={() => setBoardMode('3d')}>3D</button><button aria-pressed={boardMode === '2d'} onclick={() => setBoardMode('2d')}>2D</button></div></section>
                        {#if boardNotice}<p>{boardNotice}</p>{/if}
                        <details class="menu-card"><summary>Clocks & match state <span>◷</span></summary><div class="menu-content">
                            <div class="match-stats"><span>P1<b>{clockLabel(clockTimes?.[0])}</b><small>⚡ {game.p1Energy}</small></span><span>P2<b>{clockLabel(clockTimes?.[1])}</b><small>⚡ {game.p2Energy}</small></span></div>
                            <p class="hint">Only the active player’s clock runs. A completed turn adds 10 seconds. Time is checked when the transaction executes; network confirmation time counts.</p>
                            {#if !clockSample?.clock.enabled}<p class="hint">This older match starts with fresh clocks on its next successful turn.</p>{/if}
                            {#if timedOut}<p>P{clockSample!.clock.timedOutSlot + 1} ran out of time.</p>{/if}
                            {#if canClaimTimeout}<button onclick={() => { closeOverlay(); void commitTurn(true); }}>Claim timeout win</button>{/if}
                        </div></details>
                        <details class="menu-card"><summary>Pieces & planned actions <span>◇</span></summary><div class="menu-content">
                            {#if otherHand}<p>Opponent’s hand: {otherHand.window.map(id => { const c = game!.caps.find(c => c.id === id); return c ? capDefFor(c)?.name : ''; }).join(', ')}</p>{/if}
                            <p>{lockedBenchCount()} of your pieces in queue or cooling down.</p>
                            {#each benchCaps().filter(c => c.playerSlot === mySlot && c.availableTurn > game!.turnCount) as c}<p>{capDefFor(c)?.name}: available turn {c.availableTurn + 1}</p>{/each}
                            {#if !queuedActions.length}<p class="hint">No actions planned.</p>{/if}
                            {#each queuedActions as action}<p>{actionLabel(action, simCaps, capDefMap)}</p>{/each}
                        </div></details>
                        <details class="menu-card"><summary>How to play <span>?</span></summary><div class="menu-content">
                            <p>Reach the center of the opponent’s back row. Drag a piece from your hand to deploy, or drag a board piece along a path to move. Tap a piece to inspect its ability.</p>
                            <p>Each connecting line is one step, including diagonals. One deploy or move/attack per turn; abilities use energy. Surround captures happen automatically.</p>
                            <p>Gain 1 energy per turn, plus occupied ⚡ squares and on-board generators. Energy carries over, up to 5.</p>
                            <p>Delayed abilities wait on the stack. Newer effects resolve first when ready; open ◷ to see the timing and choose targets for negation.</p>
                        </div></details>
                        <button class="leave-game" disabled={committing || !!pendingForGame} onclick={() => { closeOverlay(); game = null; queuedActions = []; selectedCapId = null; hand = null; clockSample = null; }}>Return to lobby</button>
                        {#if !game.over}<p class="hint">Leaving the board does not pause the clock.</p>{/if}
                    {/if}
                </div>
            </dialog>
        </section>
    {/if}

    {#if !game}
    <!-- On-screen debug log (for mobile, where devtools aren't available) -->
    <details class="debug-log" bind:open={logOpen}>
        <summary>Debug log ({logLines.length})</summary>
        <div class="log-lines">
            {#each logLines as line}
                <div class="log-line">{line}</div>
            {/each}
            {#if logLines.length === 0}
                <div class="log-line muted">No events yet</div>
            {/if}
        </div>
        <button class="clear-log" onclick={() => { logLines = []; }}>Clear</button>
    </details>
    {/if}
</div>

<style>
    :global(html, body) {
        margin: 0;
        padding: 0;
        background: #0f172a;
        color: #f1f5f9;
        font-family: system-ui, -apple-system, sans-serif;
        overflow-x: clip;
        touch-action: pan-y pinch-zoom;
        -webkit-tap-highlight-color: transparent;
    }
    .wrap {
        max-width: 1320px;
        margin: 0 auto;
        padding: 0.75rem;
        min-height: 100dvh;
        display: flex;
        flex-direction: column;
    }
    .lobby { max-width:480px; width:100%; margin:0 auto; }
    .match-layout { display:grid; grid-template-columns:minmax(0, 1fr) 370px; gap:20px; align-items:start; }
    .arena { min-width:0; position:sticky; top:12px; }
    .game-sidebar { min-width:0; display:flex; flex-direction:column; gap:12px; }
    .sync-status { display:flex; justify-content:space-between; gap:12px; align-items:center; padding:12px; border:1px solid #334155; border-radius:10px; margin-bottom:12px; font-size:0.85rem; background:#132037; }

    .sync-warning { color:#fcd34d; font-size:0.85rem; line-height:1.5; }
    .opponent-last { padding:12px; background:#17263b; border-left:3px solid #fb7185; border-radius:8px; margin-bottom:12px; font-size:0.83rem; max-height:180px; overflow:auto; }
    .opponent-last p { margin:6px 0; line-height:1.5; }
    .tile.effect-focus { outline:3px solid #c4b5fd; outline-offset:-3px; }
    .stack-summary { display:block; padding:10px 12px; margin:8px 0; color:#fcd34d; border:1px solid #99713c; border-radius:8px; font-size:0.82rem; text-decoration:none; }
    @media(max-width:850px) {
        .match-layout { grid-template-columns:1fr; gap:14px; }
        .arena { position:static; }
        .hand-area { order:-1; }
        .wrap { padding-bottom:calc(88px + env(safe-area-inset-bottom)); }

    }
    :global(button), :global(input), :global(select) { min-height:44px; }
    :global(*), :global(*::before), :global(*::after) { box-sizing:border-box; }
    .topbar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 0.75rem;
    }
    .topbar h1 { margin: 0; font-size: 1.5rem; letter-spacing: 0.15em; color: #38bdf8; }
    .addr {
        font-family: ui-monospace, monospace;
        background: #1e293b;
        padding: 0.4rem 0.6rem;
        border-radius: 6px;
        font-size: 0.8rem;
        border: 1px solid #334155;
        color: #e2e8f0;
        display: flex;
        align-items: center;
        gap: 0.3rem;
        cursor: pointer;
        transition: border-color 0.15s ease;
        -webkit-tap-highlight-color: transparent;
    }
    .addr:active { border-color: #38bdf8; }
    .copy-icon { opacity: 0.6; font-size: 0.85em; }
    .dev-badge {
        background: #7c2d12;
        border: 1px solid #ea580c;
        color: #fdba74;
        font-size: 0.7rem;
        font-weight: 800;
        padding: 0.2rem 0.45rem;
        border-radius: 6px;
        letter-spacing: 0.08em;
    }

    /* Lobby */
    .lobby { display: flex; flex-direction: column; gap: 0.9rem; padding-top: 1rem; }
    .field { display: flex; flex-direction: column; gap: 0.3rem; }
    .field.row { flex-direction: row; align-items: center; gap: 0.5rem; }
    .field label { font-size: 0.8rem; font-weight: 600; color: #94a3b8; }
    input, select {
        padding: 0.7rem;
        border: 1px solid #334155;
        border-radius: 8px;
        background: #1e293b;
        color: #f1f5f9;
        font-size: 1rem;
        min-width: 0;
        flex: 1;
    }
    .hint { font-size: 0.75rem; color: #64748b; margin: 0.15rem 0 0; }
    .divider {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        color: #475569;
        font-size: 0.75rem;
        margin: 0.25rem 0;
    }
    .divider::before, .divider::after { content: ''; flex: 1; height: 1px; background: #334155; }

    button {
        padding: 0.7rem 1rem;
        border: none;
        border-radius: 8px;
        background: #334155;
        color: #f1f5f9;
        cursor: pointer;
        font-weight: 600;
        font-size: 0.95rem;
        touch-action: manipulation;
    }
    button:disabled { opacity: 0.45; cursor: not-allowed; }
    button:focus-visible, input:focus-visible, select:focus-visible, summary:focus-visible, a:focus-visible {
        outline: 2px solid #38bdf8;
        outline-offset: 2px;
    }
    button.primary { background: #2563eb; }
    button.big { padding: 1rem; font-size: 1.05rem; }

    /* Game View */
    .gameview { display: flex; flex-direction: column; gap: 0.6rem; }
    .meta { display: flex; align-items: center; gap: 0.4rem; flex-wrap: wrap; }
    .back { padding: 0.35rem 0.7rem; background: #1e293b; font-size: 0.85rem; }
    .badge {
        background: #1e293b;
        border: 1px solid #334155;
        padding: 0.2rem 0.55rem;
        border-radius: 6px;
        font-size: 0.8rem;
    }
    .turn-badge { padding: 0.2rem 0.55rem; border-radius: 6px; font-size: 0.8rem; font-weight: 700; }
    .turn-badge.p1 { background: #1d4ed8; }
    .turn-badge.p2 { background: #b91c1c; }
    .solo-note {
        background: #172554;
        border: 1px solid #1d4ed8;
        border-radius: 8px;
        padding: 0.5rem 0.75rem;
        font-size: 0.85rem;
    }
    .gameover {
        background: #052e16;
        border: 1px solid #16a34a;
        border-radius: 8px;
        padding: 0.75rem;
        text-align: center;
        font-weight: 700;
        font-size: 1.1rem;
    }
    .error {
        background: #450a0a;
        border: 1px solid #dc2626;
        border-radius: 8px;
        padding: 0.5rem 0.75rem;
        font-size: 0.85rem;
        color: #fecaca;
    }

    .tile.pending-danger::after { content: ''; position: absolute; inset: 4px; border: 1px dashed #f59e0b; border-radius: 3px; pointer-events: none; }
    .paths { position: absolute; inset: 5px; width: calc(100% - 10px); height: calc(100% - 10px); pointer-events: none; z-index: 2; }
    .paths line { stroke: #94a3b8; stroke-width: 0.55; stroke-linecap: round; opacity: 0.6; }
    .board-toolbar { display: flex; align-items: center; gap: 8px; margin: 8px 0; }


    /* Board */
    .board {
        position: relative;
        display: grid;
        grid-template-columns: repeat(var(--w), minmax(0, 1fr));
        grid-template-rows: repeat(var(--h), minmax(0, 1fr));
        gap: 3px;
        background: #1e293b;
        padding: 5px;
        border-radius: 10px;
        aspect-ratio: var(--w) / var(--h);
        max-width: 100%;
        touch-action: none;
        user-select: none;
        -webkit-user-select: none;
        -webkit-touch-callout: none;
    }
    .board.flipped { transform:rotate(180deg); }
    .board.flipped .tile, .board.flipped .piece-body { transform:rotate(180deg); }
    .tile {
        border: 1px solid #334155;
        background: #0f172a;
        border-radius: 6px;
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
    }
    .tile.void-tile { opacity: 0.25; border-style: dashed; background: transparent; }
        .tile.deploy-tile { border: 2px solid #38bdf8; }
    .tile.target-move {
        border-color: #22c55e;
        box-shadow: inset 0 0 10px rgba(34,197,94,0.35);
        animation: pulse 1.2s ease-in-out infinite;
    }
    .tile.target-fight {
        border-color: #f97316;
        box-shadow: inset 0 0 10px rgba(249,115,22,0.4);
        animation: pulse 1.2s ease-in-out infinite;
    }
    .tile.target-capture {
        border-color: #a855f7;
        box-shadow: inset 0 0 10px rgba(168,85,247,0.45);
        animation: pulse 1.2s ease-in-out infinite;
    }
    .tile.drag-over { border-color: #38bdf8; }
    .tile.drag-ok { background: #14532d; border-color: #22c55e; }
    .tile.drag-bad { background: #450a0a; border-color: #dc2626; }
    @keyframes pulse {
        0%, 100% { box-shadow: inset 0 0 6px rgba(56,189,248,0.25); }
        50% { box-shadow: inset 0 0 14px rgba(56,189,248,0.5); }
    }

    .deploy-marker { color: #38bdf8; font-size: clamp(1rem, 5vw, 1.6rem); font-weight: bold; }
    .void-marker { color: #334155; font-size: clamp(0.8rem, 4vw, 1.3rem); }
    .fight-badge {
        position: absolute;
        bottom: 2px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(249,115,22,0.9);
        color: #fff;
        font-size: 0.6rem;
        font-weight: 700;
        padding: 0 0.25rem;
        border-radius: 4px;
        pointer-events: none;
        white-space: nowrap;
    }
    .capture-badge {
        position: absolute;
        top: 2px;
        right: 3px;
        font-size: 0.8rem;
        pointer-events: none;
    }
    .drag-ring {
        position: absolute;
        inset: -2px;
        border: 2px solid #38bdf8;
        border-radius: 8px;
        pointer-events: none;
    }

    /* Pieces layer: absolute overlay, pieces glide between tiles */
    .pieces-layer {
        position: absolute;
        inset: 5px; /* match board padding */
        pointer-events: none;
        z-index: 5;
    }
    .piece {
        position: absolute;
        transform: translate(-50%, -50%);
        transition: left 0.18s cubic-bezier(0.2, 0.8, 0.3, 1), top 0.18s cubic-bezier(0.2, 0.8, 0.3, 1), opacity 0.15s ease, transform 0.15s ease;
        pointer-events: none;
    }
    .piece-body {
        width: clamp(30px, 9vw, 46px);
        height: clamp(30px, 9vw, 46px);
        border-radius: 8px;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 6px rgba(0,0,0,0.45);
    }
    .piece.p1 .piece-body { background: #2563eb; }
    .piece.p2 .piece-body { background: #dc2626; }
    .piece.selected .piece-body { outline: 3px solid #38bdf8; outline-offset: 1px; }
    .piece.drag-origin { opacity: 0.35; transform: translate(-50%, -50%) scale(0.85); }
    .piece:not(.my-piece) .piece-body { opacity: 0.92; }
    .type { font-size: clamp(0.8rem, 3.5vw, 1.15rem); font-weight: 800; color: #fff; line-height: 1; }
    .hp {
        font-size: clamp(0.5rem, 2.2vw, 0.68rem);
        background: rgba(0,0,0,0.4);
        padding: 0 0.25rem;
        border-radius: 3px;
        color: #fff;
        margin-top: 1px;
    }
    .piece-info {
        background: #1e293b;
        border: 1px solid #334155;
        border-radius: 8px;
        padding: 0.5rem 0.7rem;
    }
    .pi-name { font-weight: 700; font-size: 0.95rem; color: #e2e8f0; }
    .pi-stats { font-size: 0.78rem; color: #94a3b8; margin: 0.1rem 0; }
    .pi-ability {
        font-size: 0.82rem;
        color: #93c5fd;
        padding: 0.3rem 0;
        border-top: 1px solid #1e293b;
        margin-top: 0.3rem;
    }
    .pi-cost {
        background: #3b3305;
        color: #fde047;
        padding: 0.05rem 0.3rem;
        border-radius: 3px;
        font-size: 0.72rem;
        margin-right: 0.3rem;
    }
    .pi-passive {
        color: #a78bfa;
        font-size: 0.8rem;
        padding: 0.2rem 0 0;
        border-top: 1px solid #1e293b;
        margin-top: 0.2rem;
    }
    .passive-badge {
        position: absolute;
        bottom: -4px;
        left: -4px;
        font-size: 0.65rem;
        color: #a78bfa;
        filter: drop-shadow(0 0 2px #7c3aed);
    }
    .target-ability {
        border-color: #e879f9 !important;
        box-shadow: inset 0 0 10px rgba(232,121,249,0.4);
    }
    .ability-btn {
        background: #7c3aed;
        padding: 0.6rem 1rem;
        font-size: 0.9rem;
        width: 100%;
        border-radius: 8px;
        border: 1px solid #a78bfa;
    }
    .ability-btn:disabled { background: #1e1b4b; border-color: #312e81; }
    .locked-note {
        color: #64748b;
        font-size: 0.78rem;
        padding: 0.25rem 0;
    }
    .energy-badge {
        background: #3b3305;
        border: 1px solid #eab308;
        color: #fde047;
        padding: 0.2rem 0.55rem;
        border-radius: 6px;
        font-size: 0.8rem;
        font-weight: 700;
    }
    .shield-badge {
        font-size: clamp(0.45rem, 2vw, 0.6rem);
        background: rgba(59, 130, 246, 0.85);
        padding: 0 0.2rem;
        border-radius: 3px;
        color: #fff;
        margin-top: 1px;
    }
    .stun-badge {
        position: absolute;
        top: -6px;
        left: -6px;
        font-size: 0.8rem;
        filter: drop-shadow(0 0 3px #eab308);
    }
    .cap-mark {
        position: absolute;
        top: -6px;
        right: -6px;
        font-size: 0.85rem;
        filter: drop-shadow(0 0 3px #a855f7);
        animation: pulse 1.2s ease-in-out infinite;
    }

    /* Drag ghost */
    .drag-ghost {
        position: fixed;
        transform: translate(-50%, -50%) scale(1.12);
        pointer-events: none;
        z-index: 1000;
        filter: drop-shadow(0 8px 14px rgba(0,0,0,0.5));
    }
    .drag-ghost .piece-body {
        width: clamp(34px, 10vw, 50px);
        height: clamp(34px, 10vw, 50px);
        border-radius: 8px;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
    }
    .drag-ghost.p1 .piece-body { background: #2563eb; }
    .drag-ghost.p2 .piece-body { background: #dc2626; }
    .drag-label {
        position: absolute;
        top: -1.5em;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(249,115,22,0.95);
        color: #fff;
        font-size: 0.75rem;
        font-weight: 800;
        padding: 0.1rem 0.4rem;
        border-radius: 4px;
        white-space: nowrap;
    }

    /* Bench */
    .hand-area { min-width:0; }
    .bench { display: flex; flex-direction: column; gap: 0.3rem; }
    .bench-label { font-size: 0.75rem; color: #94a3b8; font-weight: 600; }
    .bench-pieces { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:8px; }
    .bench-card { display:flex; min-width:0; }
    .bench-inspect { padding:6px; background:#24364f; color:#cbd5e1; border:1px solid #475569; border-radius:6px; font-size:0.75rem; }
    .coordinate { position:absolute; top:3px; left:4px; font-size:9px; color:#aabbd3; pointer-events:none; }

    .bench-piece {
        background: #4c1d95;
        border: 1px solid #7c3aed;
        padding: 0.5rem 0.8rem;
        font-size: 0.85rem;
    }

    /* Queued */
    .queued { display: flex; gap: 0.4rem; flex-wrap: wrap; }
    .queued-action {
        background: #164e3a;
        border: 1px solid #16a34a;
        font-size: 0.78rem;
        padding: 0.4rem 0.6rem;
    }

    .commit {
        background: #16a34a;
        padding: 0.9rem;
        font-size: 1.05rem;
        width: 100%;
        margin-top: auto;
    }
    .commit:disabled { background: #14532d; }

    .fund-help {
        border: 1px solid #1e293b;
        border-radius: 8px;
        background: #0b1220;
    }
    .fund-body {
        padding: 0.25rem 0.7rem 0.7rem;
        display: flex;
        flex-direction: column;
        gap: 0.3rem;
    }
    .faucet-link {
        color: #38bdf8;
        font-size: 0.85rem;
        text-decoration: none;
        padding: 0.35rem 0.6rem;
        border: 1px solid #164e63;
        border-radius: 6px;
        background: #082f49;
    }
    .busy {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        color: #93c5fd;
        font-size: 0.9rem;
        justify-content: center;
    }
    .spinner {
        width: 14px;
        height: 14px;
        border: 2px solid #334155;
        border-top-color: #38bdf8;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    .debug-log {
        margin-top: 0.75rem;
        border: 1px solid #1e293b;
        border-radius: 8px;
        background: #0b1220;
        font-size: 0.75rem;
    }
    .debug-log summary {
        cursor: pointer;
        padding: 0.45rem 0.7rem;
        color: #64748b;
        user-select: none;
    }
    .log-lines {
        max-height: 180px;
        overflow-y: auto;
        padding: 0.25rem 0.7rem;
        font-family: ui-monospace, monospace;
        word-break: break-all;
    }
    .log-line { color: #94a3b8; padding: 0.12rem 0; white-space: pre-wrap; }
    .log-line.muted { color: #475569; }
    .clear-log {
        margin: 0.4rem 0.7rem 0.6rem;
        padding: 0.25rem 0.7rem;
        font-size: 0.72rem;
        background: #1e293b;
    }
    .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
    }

    .tile.goal-tile { border: 2px solid #60a5fa; }
    .tile.energy-tile { background: #443815; }
    .goal-marker { position: absolute; bottom: 2px; font-size: 0.55rem; color: #93c5fd; }

    /* Small phone tweaks */
    @media (max-width: 380px) {
        .bench-piece { padding: 0.4rem 0.6rem; font-size: 0.78rem; }
    }
    @media (prefers-reduced-motion: reduce) {
        *, *::before, *::after {
            animation-duration: 0.01ms !important;
            animation-iteration-count: 1 !important;
            transition-duration: 0.01ms !important;
        }
    }

    .wrap.playing { position:fixed; inset:0; width:100%; max-width:none; height:100dvh; min-height:0; padding:0; overflow:hidden; }
    .play-screen { height:100%; display:grid; grid-template-rows:auto minmax(0,1fr) auto; padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); background:radial-gradient(ellipse at center,#1c3049,#080f1d); }
    .play-hud { display:flex; align-items:center; gap:8px; padding:6px 10px; z-index:12; }
    .play-hud button,.turn-controls button { min-width:44px; border-radius:14px; }
    .turn-indicator { flex:1; font-size:13px; color:#c1ccdb; } .turn-indicator small { opacity:0.6; } .your-turn { color:#7dd3fc; } .hud-energy { color:#fde68a; font-size:14px; }
    .has-effects { color:#fbbf24; border-color:#b58b46; }
    .play-stage { position:relative; min-width:0; min-height:0; display:grid; place-items:center; container-type:size; }
    .play-stage .board { width:min(96cqw,calc(96cqh * var(--w) / var(--h))); height:min(96cqh,calc(96cqw * var(--h) / var(--w))); }
    .stack-chip,.target-prompt { position:absolute; top:4px; left:50%; transform:translateX(-50%); max-width:90%; width:max-content; font-size:11px; z-index:12; background:#18243ae8; border-radius:20px; padding:6px 14px; color:#fcd34d; }
    .target-prompt { top:52px; color:#c4b5fd; }
    .play-dock { position:relative; width:100%; max-width:620px; justify-self:center; padding:4px 12px 0; z-index:15; }
    .hand-strip { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:6px; height:62px; }
    .hand-strip button { touch-action:none; user-select:none; display:flex; flex-direction:column; align-items:center; justify-content:center; padding:4px; border-radius:12px; background:#17273be8; }
    .hand-strip b { font-size:24px; line-height:28px; color:#8ac5ff; } .hand-strip span { font-size:10px; } .hand-strip button.selected { border-color:#7dd3fc; background:#244b69; transform:translateY(-3px); }
    .empty-hand { grid-column:1/-1; align-self:center; text-align:center; color:#758ba5; }
    .turn-controls { display:flex; align-items:center; gap:10px; padding-top:6px; } .action-dots { color:#7dd3fc; font-size:18px; } .turn-controls .submit-turn { flex:1; background:#166654; border-color:#3aab89; }
    .connection-line { height:22px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; text-align:center; font-size:11px; color:#e9ba70; padding:3px; }
    .selection-card { position:relative; margin-bottom:6px; width:100%; max-height:min(25dvh,170px); overflow:auto; padding:10px 12px; border:1px solid #58748e; border-radius:16px; background:#101e30f5; box-shadow:0 8px 24px #0006; }
    .selection-card.hover-only { position:absolute; bottom:100%; left:12px; width:calc(100% - 24px); max-height:200px; }
    .selection-title { display:flex; align-items:center; gap:8px; font-size:13px; } .selection-title span { margin-left:auto; font-size:11px; color:#adc2d7; } .selection-title button { padding:4px; min-width:44px; }
    .selection-card p { font-size:12px; line-height:1.4; margin:6px 0; color:#c8d9e9; } .selection-card .passive-description { color:#c4b5fd; } .selection-action { width:100%; background:#49317a; }
    .end-card { position:absolute; z-index:16; text-align:center; padding:24px; border-radius:18px; background:#101e30ed; }
    .game-sheet { color:#e2e8f0; background:#101e30; border:1px solid #4a627c; border-radius:20px; width:min(94vw,480px); max-height:80dvh; padding:0; }
    .game-sheet::backdrop { background:#020817aa; backdrop-filter:blur(4px); }
    .game-sheet > header { position:sticky; top:0; display:flex; align-items:center; justify-content:space-between; background:#101e30; padding:10px 14px; z-index:1; }
    .sheet-body { display:flex; flex-direction:column; gap:10px; padding:0 14px 18px; } .sheet-body p { font-size:13px; line-height:1.5; } .stage-notice { color:#91abc5; }

    @media(max-height:500px) and (orientation:landscape) { .play-screen { grid-template-columns:minmax(0,1fr) 190px; grid-template-rows:auto minmax(0,1fr); } .play-top { grid-column:1/-1; } .play-dock { align-self:end; padding:8px; } .hand-strip { grid-template-columns:repeat(2,minmax(0,1fr)); height:130px; } .selection-card { max-height:130px; } }
    @media(prefers-reduced-motion:reduce) { .piece { transition:none; } .tile { animation:none; } }

    .drag-preview { position:fixed; transform:translate(-50%,-110%); z-index:50; pointer-events:none; display:flex; flex-direction:column; align-items:center; background:#17283bf2; border:2px solid #a8b4c5; border-radius:14px; padding:8px 12px; box-shadow:0 6px 20px #0007; }
    .drag-preview b { font-size:28px; } .drag-preview span { font-size:11px; } .drag-preview.legal { border-color:#4ade80; color:#bbf7d0; }
    .play-top { z-index:12; }
    .clock-strip { display:flex; justify-content:center; gap:6px; padding:0 10px 4px; }
    .clock-strip > span { display:flex; align-items:center; gap:10px; min-width:104px; padding:3px 10px; border:1px solid #34455b; border-radius:8px; color:#94a8bf; background:#101e30; }
    .clock-strip small { font-size:10px; } .clock-strip b { font-size:15px; font-variant-numeric:tabular-nums; margin-left:auto; }
    .clock-strip > .running { color:#b6edff; border-color:#519bbb; background:#19394b; } .clock-strip > .low { color:#fda4af; border-color:#a74659; }
    .lobby-intro { padding:18px 0 12px; } .eyebrow { color:#74bfd8; font-size:10px; font-weight:700; letter-spacing:0.16em; }
    .lobby-intro h2 { font-size:clamp(30px,7vw,42px); line-height:1.12; letter-spacing:-0.04em; margin:12px 0; }
    .lobby-intro p { color:#a8b8cc; font-size:14px; line-height:1.5; max-width:340px; }
    .format-chip { display:inline-block; padding:6px 10px; border:1px solid #39516a; border-radius:20px; font-size:12px; color:#c0d5e9; }
    .menu-card { background:#142338; border:1px solid #30455d; border-radius:16px; overflow:hidden; }
    .menu-card summary { display:flex; align-items:center; justify-content:space-between; gap:12px; min-height:54px; padding:12px 16px; cursor:pointer; font-size:14px; font-weight:600; list-style:none; }
    .menu-card summary::-webkit-details-marker { display:none; } .menu-card summary span { color:#91b5d0; }
    .menu-card[open] summary { border-bottom:1px solid #30455d; } .menu-content { display:flex; flex-direction:column; gap:12px; padding:16px; }
    .menu-content p { margin:0; line-height:1.5; } .new-match { display:flex; flex-direction:column; padding:18px; gap:14px; }
    .new-match .hint,.menu-content .hint,.lobby > .hint,.sheet-body > .hint { color:#a4b5c9; line-height:1.5; }
    .play-bot { display:flex; align-items:center; justify-content:space-between; text-align:left; border-radius:12px; background:linear-gradient(115deg,#23799b,#2859ae); }
    button.primary.play-bot { background:linear-gradient(115deg,#23799b,#2859ae); } .play-bot small { display:block; font-size:11px; margin-top:4px; font-weight:400; color:#d0e7fb; }
    .solo-button { background:#20334b; font-size:13px; border-radius:12px; } .resume-game { display:flex; justify-content:space-between; background:#163c3d; border:1px solid #367672; border-radius:12px; font-size:13px; }
    .match-summary { padding:4px 2px 10px; } .match-summary h2 { font-size:24px; margin:8px 0 4px; } .match-summary p { margin:0; color:#a5b8ce; }
    .menu-actions { display:grid; grid-template-columns:1fr 1fr; gap:8px; } .menu-actions button { font-size:13px; }
    .display-settings { display:flex; justify-content:space-between; align-items:center; padding:8px 14px; font-size:13px; }
    .segmented { display:flex; padding:3px; gap:3px; background:#0b1727; border-radius:10px; } .segmented button { background:transparent; font-size:12px; min-width:48px; } .segmented button[aria-pressed="true"] { background:#285675; color:#e0f4ff; }
    .match-stats { display:grid; grid-template-columns:1fr 1fr; gap:12px; } .match-stats > span { display:flex; flex-direction:column; gap:6px; align-items:center; font-size:12px; color:#b5c9dd; } .match-stats b { font-size:26px; font-variant-numeric:tabular-nums; color:#edf6ff; }
    .leave-game { margin-top:8px; background:transparent; border:1px solid #4a627c; }
    .timeout-result { padding:12px; border-radius:12px; background:#19394b; }
    @media(min-width:700px) { .lobby { padding-top:32px; padding-bottom:40px; } .topbar { width:100%; max-width:960px; align-self:center; } }
    .board.routed .tile.void-tile { visibility:hidden; }
    .board.routed .tile.connector-tile { visibility:visible; opacity:1; background:#26374e; border:0; border-radius:2px; }
</style>
