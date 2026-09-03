<script lang="ts">
    import { onMount } from 'svelte';
    import {
        connect, getAccount, createGame, createSoloGame, takeTurn, getGame,
        getLayout, isValidStep, isSurroundedIn, LAYOUTS, LAYOUT_PERIMETER_5X5, isDevMode,
        getHand,
        type ChainGame, type ChainCap, type TurnAction, type LayoutConfig, type ChainHand, CAP_STATS,
    } from '$lib/dojo/client';

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

    let opponent = $state('');
    let selectedLayout = $state<number>(LAYOUT_PERIMETER_5X5);
    let gameIdInput = $state('1');
    let game = $state<ChainGame | null>(null);

    let hand = $state<ChainHand | null>(null);
    let selectedCapId = $state<number | null>(null);
    let queuedActions: TurnAction[] = $state([]);
    let committing = $state(false);

    let activeLayout = $derived<LayoutConfig>(getLayout(game ? game.layout : selectedLayout));
    let isSolo = $derived<boolean>(!!game && game.player1 === game.player2);

    // Optimistic simulation: game caps with queued actions applied.
    // Powers rendering + validation so multi-action turns feel real.
    let simCaps = $derived.by((): ChainCap[] => {
        if (!game) return [];
        const caps = game.caps.map(c => ({ ...c }));
        for (const qa of queuedActions) {
            const mover = caps.find(c => c.id === qa.capId);
            if (!mover) continue;
            const target = caps.find(c => c.x === qa.x && c.y === qa.y);
            if (qa.kind === 'Play') {
                if (mover.x === null) { mover.x = qa.x; mover.y = qa.y; }
            } else if (qa.kind === 'Move') {
                if (mover.x === null || mover.y === null) continue;
                if (target && target.id !== mover.id) {
                    const isEnemy = target.owner !== mover.owner;
                    const atk = CAP_STATS[mover.capType]?.[1] ?? 0;
                    if (isEnemy && target.health <= atk) {
                        // kill: mover takes the tile
                        target.x = null; target.y = null;
                        mover.x = qa.x; mover.y = qa.y;
                    }
                    // survive: nothing changes positionally
                } else if (!target) {
                    mover.x = qa.x; mover.y = qa.y;
                }
            } else if (qa.kind === 'ClaimCapture') {
                if (target) { target.x = null; target.y = null; }
            }
        }
        return caps;
    });


    // Board geometry for pointer → cell hit-testing
    let boardEl: HTMLDivElement | undefined = $state();

    function cellFromPoint(px: number, py: number): { x: number; y: number } | null {
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

    function myOwner(): string | null {
        if (!account || !game) return null;
        return isSolo ? turnPlayerAddress() : account;
    }

    function isMyCap(c: ChainCap): boolean {
        return myOwner() !== null && c.owner === myOwner();
    }

    function isMyTurn(): boolean {
        if (!game || !account) return false;
        return turnPlayerAddress() === account;
    }

    function canAct(): boolean {
        return !!game && !game.over && isMyTurn();
    }

    function benchCaps(): ChainCap[] {
        return simCaps.filter(c => c.x === null);
    }

    function myBenchCaps(): ChainCap[] {
        const owner = myOwner();
        if (!owner) return [];
        let candidates = benchCaps().filter(c => c.owner === owner);
        // Hand filter: only pieces in the current hand window are playable
        if (hand) {
            const windowSet = new Set(hand.window);
            candidates = candidates.filter(c => windowSet.has(c.id));
        }
        return candidates;
    }

    /** Bench pieces waiting for the hand cycle to come around. */
    function lockedBenchCount(): number {
        const owner = myOwner();
        if (!owner) return 0;
        const all = benchCaps().filter(c => c.owner === owner);
        return all.length - myBenchCaps().length;
    }

    function myBoardCaps(): ChainCap[] {
        const owner = myOwner();
        if (!owner) return [];
        return simCaps.filter(c => c.x !== null && c.owner === owner);
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
        if (cap.x === null || cap.y === null) return out;
        const dmg = CAP_STATS[cap.capType]?.[1] ?? 0;
        for (let dx = -1; dx <= 1; dx++) {
            for (let dy = -1; dy <= 1; dy++) {
                if (dx === 0 && dy === 0) continue;
                const x = cap.x + dx, y = cap.y + dy;
                if (!activeLayout.isWalkable(x, y)) continue;
                if (!isValidStep(game!.layout, [cap.x, cap.y], [x, y])) continue;
                const occ = capAt(x, y);
                if (!occ) out.set(`${x},${y}`, { type: 'move' });
                else if (occ.owner !== myOwner() && occ.id !== cap.id) out.set(`${x},${y}`, { type: 'fight', dmg });
            }
        }
        return out;
    }

    /** Chained (surrounded) enemies on the sim board — capturable by any of my board caps. */
    let captureTargets = $derived.by((): { x: number; y: number }[] => {
        if (!game) return [];
        const g = game;
        const owner = myOwner();
        if (!owner || myBoardCaps().length === 0) return [];
        return simCaps
            .filter(c => c.x !== null && c.y !== null && c.owner !== owner &&
                         isSurroundedIn(simCaps, g.layout, c.x!, c.y!))
            .map(c => ({ x: c.x!, y: c.y! }));
    });

    function isCaptureTarget(x: number, y: number): boolean {
        return captureTargets.some(t => t.x === x && t.y === y);
    }

    // Action queueing (shared by tap + drag)
    function queueAction(capId: number, kind: TurnAction['kind'], x: number, y: number) {
        queuedActions = [...queuedActions, { capId, kind, x, y }];
        const labels: Record<string, string> = { Play: '⬇ deploy', Move: '→ move', ClaimCapture: '⛓ capture' };
        status = `Queued ${labels[kind]} → (${x},${y})`;
        errorMsg = null;
        log(`Queued ${kind} → (${x},${y})`);
        vibrate(15);
    }

    function tryDeploy(capId: number): boolean {
        const [dx, dy] = deploySpot();
        if (capAt(dx, dy)) {
            errorMsg = 'Deploy spot is occupied';
            log('Deploy spot occupied', 'error');
            return false;
        }
        queueAction(capId, 'Play', dx, dy);
        return true;
    }

    function tryMove(capId: number, x: number, y: number): boolean {
        const cap = capById(capId);
        if (!cap || cap.x === null || cap.y === null) return false;
        const targets = moveTargets(cap);
        const t = targets.get(`${x},${y}`);
        if (!t) return false;
        queueAction(capId, 'Move', x, y);
        return true;
    }

    function tryCapture(x: number, y: number): boolean {
        const claimer = selectedCapId != null
            ? capById(selectedCapId)
            : myBoardCaps()[0];
        if (!claimer || claimer.x === null) {
            errorMsg = 'You need a piece on the board to capture';
            log('Capture needs a board piece', 'error');
            return false;
        }
        queueAction(claimer.id, 'ClaimCapture', x, y);
        selectedCapId = null;
        return true;
    }

    // Tap resolution
    function onTapCell(x: number, y: number) {
        if (!canAct() || !activeLayout.isWalkable(x, y)) return;
        const occ = capAt(x, y);

        if (occ && isMyCap(occ)) {
            selectedCapId = selectedCapId === occ.id ? null : occ.id;
            return;
        }

        // capture affordance: tap a chained enemy
        if (occ && isCaptureTarget(x, y)) {
            tryCapture(x, y);
            return;
        }

        if (selectedCapId != null) {
            if (tryMove(selectedCapId, x, y)) {
                // keep selection? deselect for clarity
                selectedCapId = null;
                return;
            }
        }

        // nothing matched — deselect
        selectedCapId = null;
    }

    function onTapBench(capId: number) {
        if (!canAct()) return;
        if (tryDeploy(capId)) {
            selectedCapId = null;
        }
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
        if (!cap) { downInfo = null; return; }
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
            drag.valid = !capAt(over.x, over.y) && isDeploySpot(over.x, over.y);
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
            tryDeploy(capId);
        } else {
            tryMove(capId, over.x, over.y);
            selectedCapId = null;
        }
    }

    function onPointerDown(e: PointerEvent) {
        if (!canAct()) return;
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        const px = e.clientX, py = e.clientY;

        const benchId = benchCapFromPoint(px, py);
        if (benchId !== null) {
            downInfo = { px, py, capId: benchId, fromBench: true };
            (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
            return;
        }
        const cell = cellFromPoint(px, py);
        if (cell) {
            const occ = capAt(cell.x, cell.y);
            if (occ && isMyCap(occ)) {
                downInfo = { px, py, capId: occ.id, fromBench: false, cell };
            } else {
                downInfo = { px, py, cell };
            }
            (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
        }
    }

    function onPointerMove(e: PointerEvent) {
        if (!downInfo) return;
        const dist = Math.hypot(e.clientX - downInfo.px, e.clientY - downInfo.py);
        if (!drag && dist > 8 && downInfo.capId !== undefined) {
            beginDragIfCap(e.clientX, e.clientY);
        }
        if (drag) evaluateDragTarget(e.clientX, e.clientY);
    }

    function onPointerUp(e: PointerEvent) {
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
            // tap on bench piece → instant deploy
            onTapBench(downInfo.capId);
        } else if (dist <= 8 && downInfo.cell && upCell &&
                   upCell.x === downInfo.cell.x && upCell.y === downInfo.cell.y) {
            onTapCell(upCell.x, upCell.y);
        } else if (dist <= 8 && upBench !== null && downInfo.capId === upBench) {
            onTapBench(upBench);
        }
        downInfo = null;
    }

    function onPointerCancel() {
        drag = null;
        downInfo = null;
    }

    // Lobby / connection flows (unchanged behavior)
    async function handleConnect() {
        errorMsg = null;
        busy = 'Opening Controller…';
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

    async function discoverMyGame(): Promise<number | null> {
        const PROBE = 40;
        const results = await Promise.allSettled(
            Array.from({ length: PROBE }, (_, i) => getGame(i + 1))
        );
        let best: number | null = null;
        results.forEach((r) => {
            if (r.status === 'fulfilled' && r.value) {
                const g = r.value;
                if (g.player1 === account || g.player2 === account) {
                    if (best === null || g.id > best) best = g.id;
                }
            }
        });
        return best;
    }

    async function handleCreateSolo() {
        errorMsg = null;
        if (!account) { errorMsg = 'Connect first'; return; }
        busy = 'Creating solo game…';
        log(`Creating solo game (${getLayout(selectedLayout).name})`);
        try {
            await createSoloGame(selectedLayout);
            log('Solo game tx confirmed');
            busy = 'Finding your game…';
            const id = await discoverMyGame();
            if (id == null) {
                status = 'Game created — enter its id manually to load';
                log('Could not auto-find game id', 'error');
                return;
            }
            gameIdInput = String(id);
            await handleLoad();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Create failed: ${errorMsg}`, 'error');
        } finally {
            busy = null;
        }
    }

    async function handleCreate() {
        errorMsg = null;
        if (!account) { errorMsg = 'Connect first'; return; }
        const opp = opponent.trim();
        if (!opp) { errorMsg = 'Enter an opponent address'; return; }
        busy = 'Creating game…';
        log(`Creating game vs ${opp.slice(0, 10)}…`);
        try {
            await createGame(opp, selectedLayout);
            log('Game tx confirmed');
            busy = 'Finding your game…';
            const id = await discoverMyGame();
            if (id == null) {
                status = 'Game created — enter its id manually to load';
                log('Could not auto-find game id', 'error');
                return;
            }
            gameIdInput = String(id);
            await handleLoad();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Create failed: ${errorMsg}`, 'error');
        } finally {
            busy = null;
        }
    }

    async function handleLoad() {
        errorMsg = null;
        try {
            const id = Number(gameIdInput);
            if (Number.isNaN(id) || id <= 0) throw new Error('Enter a valid game id');
            game = await getGame(id);
            if (!game) throw new Error(`Game ${id} not found`);
            // Load the current turn player's hand (public info)
            const slot = game.turnCount % 2;
            hand = await getHand(id, slot);
            selectedCapId = null;
            queuedActions = [];
            status = `Loaded game #${id}`;
            log(`Loaded game #${id} (turn ${game.turnCount}, layout ${game.layout})`);
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Load failed: ${errorMsg}`, 'error');
        }
    }

    function colorFor(c: ChainCap): string {
        if (!game) return '#3b82f6';
        return c.owner === game.player1 ? '#3b82f6' : '#ef4444';
    }

    async function commitTurn() {
        if (!game || queuedActions.length === 0) return;
        errorMsg = null;
        committing = true;
        log(`Submitting ${queuedActions.length} action(s)…`);
        try {
            await takeTurn(game.id, queuedActions);
            queuedActions = [];
            status = 'Turn submitted';
            log('Turn tx confirmed');
            await handleLoad();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Turn failed: ${errorMsg}`, 'error');
        } finally {
            committing = false;
        }
    }

    function removeQueuedAction(index: number) {
        queuedActions = queuedActions.filter((_, i) => i !== index);
    }

    function pct(pos: number, size: number): string {
        return `${((pos + 0.5) / size) * 100}%`;
    }

    onMount(() => {});
</script>

<svelte:head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <meta name="theme-color" content="#0f172a" />
</svelte:head>

<div class="wrap">
    <header class="topbar">
        <h1>CAPS</h1>
        {#if account}
            {#if devMode}<span class="dev-badge">DEV</span>{/if}
            <button class="addr" onclick={copyAddress} title="Tap to copy full address">
                {addrCopied ? '✓ Copied' : `${account.slice(0, 6)}…${account.slice(-4)}`}
                <span class="copy-icon">{addrCopied ? '' : '⧉'}</span>
            </button>
        {/if}
    </header>

    {#if !game}
        <!-- Lobby -->
        <section class="lobby">
            {#if errorMsg}
                <div class="error">{errorMsg}</div>
            {/if}
            {#if !account}
                <button class="primary big" onclick={handleConnect} disabled={busy !== null}>
                    {devMode ? 'Enter Dev Mode' : 'Connect Controller'}
                </button>
                {#if busy}
                    <div class="busy"><span class="spinner"></span>{busy}</div>
                {/if}
            {:else}
                <div class="field">
                    <label for="layout-select">Board Layout</label>
                    <select id="layout-select" bind:value={selectedLayout}>
                        {#each Object.values(LAYOUTS) as l}
                            <option value={l.id}>{l.name}</option>
                        {/each}
                    </select>
                    <p class="hint">{getLayout(selectedLayout).description}</p>
                </div>

                {#if busy}
                    <div class="busy"><span class="spinner"></span>{busy}</div>
                {/if}

                <button class="primary big" onclick={handleCreateSolo} disabled={busy !== null}>
                    🎮 Play Solo (Both Sides)
                </button>

                <details class="fund-help">
                    <summary>⛽ Fund account (for gas when paymaster fails)</summary>
                    <div class="fund-body">
                        <p class="hint">1. Tap the address above to copy it.</p>
                        <p class="hint">2. Get free Sepolia STRK from a faucet:</p>
                        <a class="faucet-link" href="https://starknet-faucet.vercel.app/" target="_blank" rel="noopener">starknet-faucet.vercel.app ↗</a>
                        <a class="faucet-link" href="https://sepolia.starkscan.co/faucet" target="_blank" rel="noopener">sepolia.starkscan.co/faucet ↗</a>
                        <p class="hint">3. Paste your address there, receive STRK, then retry your turn.</p>
                    </div>
                </details>
                {#if busy}
                    <div class="busy"><span class="spinner"></span>{busy}</div>
                {/if}

                <div class="divider"><span>or play vs opponent</span></div>

                <div class="field">
                    <label for="opp">Opponent Address</label>
                    <input id="opp" bind:value={opponent} placeholder="0x…" />
                </div>
                <button class="big" onclick={handleCreate} disabled={!opponent.trim() || busy !== null}>Create Game</button>

                <div class="divider"><span>load existing</span></div>

                <div class="field row">
                    <input bind:value={gameIdInput} type="number" placeholder="Game id" />
                    <button onclick={handleLoad}>Load</button>
                </div>
            {/if}
        </section>
    {:else}
        <!-- Game View -->
        <section class="gameview">
            <div class="meta">
                <button class="back" onclick={() => { game = null; queuedActions = []; selectedCapId = null; hand = null; }}>← Lobby</button>
                <span class="badge">#{game.id}</span>
                <span class="turn-badge {game.turnCount % 2 === 0 ? 'p1' : 'p2'}">
                    {game.turnCount % 2 === 0 ? "P1" : "P2"}
                </span>
                <span class="energy-badge" title="Energy this turn">⚡ {game.energy}</span>
            </div>

            {#if game.over}
                <div class="gameover">
                    {game.winner === '0' ? 'Draw!' : `Winner: ${game.winner.slice(0, 10)}…`}
                </div>
            {/if}

            {#if isSolo && isMyTurn()}
                <div class="solo-note">
                    Playing both sides — currently controlling <b>{game.turnCount % 2 === 0 ? 'P1 (Blue)' : 'P2 (Red)'}</b>
                </div>
            {/if}

            {#if errorMsg}
                <div class="error">{errorMsg}</div>
            {/if}

            <!-- Board: static tiles + gliding pieces layer -->
            <div
                class="board"
                role="application"
                aria-label="Game board"
                bind:this={boardEl}
                style="--w:{activeLayout.width};--h:{activeLayout.height}"
                onpointerdown={onPointerDown}
                onpointermove={onPointerMove}
                onpointerup={onPointerUp}
                onpointercancel={onPointerCancel}
            >
                {#each Array.from({ length: activeLayout.height * activeLayout.width }, (_, idx) => idx) as idx}
                    {@const x = idx % activeLayout.width}
                    {@const y = Math.floor(idx / activeLayout.width)}
                    {@const walkable = activeLayout.isWalkable(x, y)}
                    {@const isDeploy = isDeploySpot(x, y)}
                    {@const occ = capAt(x, y)}
                    {@const selCap = selectedCapId != null ? capById(selectedCapId) : null}
                    {@const selTargets = selCap && selCap.x !== null && selCap.y !== null ? moveTargets(selCap) : null}
                    {@const targetInfo = selTargets?.get(`${x},${y}`)}
                    {@const isCapture = !occ && isCaptureTarget(x, y)}
                    {@const dragOver = drag?.over?.x === x && drag?.over?.y === y}
                    <div
                        class="tile"
                        class:void-tile={!walkable}
                        class:deploy-tile={isDeploy && !occ}
                        class:target-move={!!targetInfo && targetInfo.type === 'move'}
                        class:target-fight={!!targetInfo && targetInfo.type === 'fight'}
                        class:target-capture={isCapture}
                        class:drag-over={dragOver}
                        class:drag-ok={dragOver && drag?.valid}
                        class:drag-bad={dragOver && drag != null && !drag.valid}
                        data-cell="{x},{y}"
                    >
                        {#if isDeploy && !occ}
                            <div class="deploy-marker">↓</div>
                        {:else if !walkable}
                            <div class="void-marker">·</div>
                        {/if}
                        {#if targetInfo && targetInfo.type === 'fight'}
                            <div class="fight-badge">⚔ {targetInfo.dmg}</div>
                        {/if}
                        {#if isCapture}
                            <div class="capture-badge">⛓</div>
                        {/if}
                        {#if dragOver}
                            <div class="drag-ring"></div>
                        {/if}
                    </div>
                {/each}

                <!-- Pieces: absolutely positioned, glide between tiles -->
                <div class="pieces-layer">
                    {#each simCaps as c (c.id)}
                        {#if c.x !== null && c.y !== null}
                            {@const isDragging = drag?.capId === c.id}
                            <div
                                class="piece p{c.owner === game.player1 ? '1' : '2'}"
                                class:tower={c.capType === 0}
                                class:selected={selectedCapId === c.id}
                                class:drag-origin={isDragging}
                                class:my-piece={isMyCap(c)}
                                style="left:{pct(c.x, activeLayout.width)};top:{pct(c.y, activeLayout.height)}"
                            >
                                <div class="piece-body">
                                    <div class="type">{c.capType === 0 ? '★' : c.capType}</div>
                                    <div class="hp">{c.health}</div>
                                    {#if c.shield > 0}<div class="shield-badge">🛡{c.shield}</div>{/if}
                                    {#if c.stunnedTurns > 0}<div class="stun-badge">💫</div>{/if}
                                </div>
                                {#if isCaptureTarget(c.x, c.y)}
                                    <div class="cap-mark">⛓</div>
                                {/if}
                            </div>
                        {/if}
                    {/each}
                </div>
            </div>

            <!-- Drag ghost (follows finger) -->
            {#if drag}
                {@const dc = capById(drag.capId)}
                {#if dc}
                    <div
                        class="drag-ghost p{dc.owner === game.player1 ? '1' : '2'}"
                        class:tower={dc.capType === 0}
                        style="left:{drag.px}px;top:{drag.py}px"
                    >
                        <div class="piece-body">
                            <div class="type">{dc.capType === 0 ? '★' : dc.capType}</div>
                            <div class="hp">{dc.health}</div>
                        </div>
                        {#if drag.label}
                            <div class="drag-label">{drag.label}</div>
                        {/if}
                    </div>
                {/if}
            {/if}

            <!-- Hints -->
            {#if drag}
                <p class="hint">
                    {#if drag.fromBench}Drop on the ⬇ deploy spot to deploy
                    {:else if drag.valid}Release to {drag.label ? 'attack' : 'move'}
                    {:else}Release on a highlighted tile
                    {/if}
                </p>
            {:else if selectedCapId != null}
                <p class="hint">Tap or drag a highlighted tile — ⚔ means attack</p>
            {:else if captureTargets.length > 0 && isMyTurn()}
                <p class="hint">⛓ A surrounded enemy can be captured — tap it</p>
            {/if}

            <!-- Bench -->
            {#if lockedBenchCount() > 0}
                <div class="locked-note">
                    🔒 {lockedBenchCount()} piece{lockedBenchCount() === 1 ? '' : 's'} cycling back into your hand…
                </div>
            {/if}
            {#if myBenchCaps().length > 0}
                <div class="bench">
                    <span class="bench-label">Bench ({game.turnCount % 2 === 0 ? 'P1' : 'P2'})</span>
                    <div class="bench-pieces">
                        {#each myBenchCaps() as c (c.id)}
                            <button
                                class="bench-piece"
                                data-bench={c.id}
                            >{c.capType === 0 ? '★' : c.capType} · {c.health}hp</button>
                        {/each}
                    </div>
                </div>
            {/if}

            <!-- Queued Actions -->
            {#if queuedActions.length > 0}
                <div class="queued">
                    {#each queuedActions as qa, i}
                        <button class="queued-action" onclick={() => removeQueuedAction(i)}>
                            {qa.kind === 'ClaimCapture' ? '⛓' : qa.kind} ({qa.x},{qa.y}) ✕
                        </button>
                    {/each}
                </div>
            {/if}

            <!-- Commit -->
            <button class="commit" onclick={commitTurn} disabled={queuedActions.length === 0 || committing || busy !== null}>
                {committing || busy ? (committing ? 'Submitting…' : busy) : `Submit Turn (${queuedActions.length})`}
            </button>
        </section>
    {/if}

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
</div>

<style>
    :global(html, body) {
        margin: 0;
        padding: 0;
        background: #0f172a;
        color: #f1f5f9;
        font-family: system-ui, -apple-system, sans-serif;
        overscroll-behavior: none;
        -webkit-tap-highlight-color: transparent;
    }
    .wrap {
        max-width: 480px;
        margin: 0 auto;
        padding: 0.75rem;
        min-height: 100dvh;
        display: flex;
        flex-direction: column;
    }
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
    .piece.tower .piece-body { border-radius: 8px 8px 16px 16px; }
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
    .drag-ghost.tower .piece-body { border-radius: 8px 8px 16px 16px; }
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
    .bench { display: flex; flex-direction: column; gap: 0.3rem; }
    .bench-label { font-size: 0.75rem; color: #94a3b8; font-weight: 600; }
    .bench-pieces { display: flex; gap: 0.4rem; flex-wrap: wrap; }
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
    .fund-help summary {
        cursor: pointer;
        padding: 0.5rem 0.7rem;
        color: #94a3b8;
        font-size: 0.85rem;
        user-select: none;
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

    /* Small phone tweaks */
    @media (max-width: 380px) {
        .bench-piece { padding: 0.4rem 0.6rem; font-size: 0.78rem; }
    }
</style>