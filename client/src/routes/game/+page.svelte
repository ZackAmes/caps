<script lang="ts">
    import { onMount } from 'svelte';
    import {
        connect, isConnected, getAccount, createGame, createSoloGame, takeTurn, getGame,
        getLayout, isValidStep, isSurrounded, LAYOUTS, LAYOUT_PERIMETER_5X5, isDevMode,
        type ChainGame, type ChainCap, type TurnAction, type LayoutConfig, CAP_STATS,
    } from '$lib/dojo/client';

    let account = $state<string | null>(null);
    let status = $state<string>('Disconnected');
    let errorMsg = $state<string | null>(null);

    let opponent = $state('');
    let selectedLayout = $state<number>(LAYOUT_PERIMETER_5X5);
    let gameIdInput = $state('1');
    let game = $state<ChainGame | null>(null);

    // Turn editor
    let selectedCapId = $state<number | null>(null);
    let pendingMode = $state<'move' | 'attack' | 'play' | 'capture' | null>(null);
    let queuedActions: TurnAction[] = $state([]);
    let committing = $state(false);

    let activeLayout = $derived<LayoutConfig>(getLayout(game ? game.layout : selectedLayout));
    let isSolo = $derived<boolean>(!!game && game.player1 === game.player2);

    // Busy indicator + on-screen log so mobile users can debug without devtools
    let busy = $state<string | null>(null);
    let logLines = $state<string[]>([]);
    let logOpen = $state(false);

    let addrCopied = $state(false);
    const devMode = isDevMode();

    async function copyAddress() {
        if (!account) return;
        try {
            await navigator.clipboard.writeText(account);
        } catch {
            // Clipboard API can be blocked (insecure context / iOS); fall back
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

    function log(msg: string, kind: 'info' | 'error' = 'info') {
        const t = new Date().toLocaleTimeString([], { hour12: false });
        logLines = [...logLines.slice(-49), `[${t}] ${kind === 'error' ? '\u274c' : '\u00b7'} ${msg}`];
        if (kind === 'error') logOpen = true;
    }

    async function handleConnect() {
        errorMsg = null;
        busy = 'Opening Controller\u2026';
        log('Connect requested');
        try {
            const acc = await connect();
            account = acc.address;
            status = 'Connected';
            log(`Connected as ${acc.address.slice(0, 10)}\u2026`);
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Connect failed: ${errorMsg}`, 'error');
        } finally {
            busy = null;
        }
    }

    /** After a create tx mines, find the newest game belonging to us. */
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

    async function handleCreate() {
        errorMsg = null;
        if (!account) { errorMsg = 'Connect first'; return; }
        const opp = opponent.trim();
        if (!opp) { errorMsg = 'Enter an opponent address'; return; }
        busy = 'Creating game\u2026';
        log(`Creating game vs ${opp.slice(0, 10)}\u2026`);
        try {
            await createGame(opp, selectedLayout);
            log('Game tx confirmed');
            busy = 'Finding your game\u2026';
            const id = await discoverMyGame();
            if (id == null) {
                status = 'Game created \u2014 enter its id manually to load';
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

    async function handleCreateSolo() {
        errorMsg = null;
        if (!account) { errorMsg = 'Connect first'; return; }
        busy = 'Creating solo game\u2026';
        log(`Creating solo game (${getLayout(selectedLayout).name})`);
        try {
            await createSoloGame(selectedLayout);
            log('Solo game tx confirmed');
            busy = 'Finding your game\u2026';
            const id = await discoverMyGame();
            if (id == null) {
                status = 'Game created \u2014 enter its id manually to load';
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
            selectedCapId = null;
            pendingMode = null;
            queuedActions = [];
            status = `Loaded game #${id}`;
            log(`Loaded game #${id} (turn ${game.turnCount}, layout ${game.layout})`);
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
            log(`Load failed: ${errorMsg}`, 'error');
        }
    }

    function turnPlayerAddress(): string | null {
        if (!game) return null;
        return game.turnCount % 2 === 0 ? game.player1 : game.player2;
    }

    function isMyCap(c: ChainCap): boolean {
        if (!account || !game) return false;
        if (isSolo) {
            // In solo mode, control whichever side currently has the turn
            return c.owner === turnPlayerAddress();
        }
        return c.owner === account;
    }

    function isMyTurn(): boolean {
        if (!game || !account) return false;
        return turnPlayerAddress() === account;
    }

    function isSoloPlayerTurnSide(): boolean {
        if (!game || !account || !isSolo) return false;
        return turnPlayerAddress() === account;
    }

    function capAt(x: number, y: number): ChainCap | undefined {
        return game?.caps.find(c => c.x === x && c.y === y) ?? undefined;
    }

    function benchCaps(): ChainCap[] {
        if (!game) return [];
        return game.caps.filter(c => c.x === null);
    }

    function myBenchCaps(): ChainCap[] {
        if (!game || !account) return [];
        const turnOwner = turnPlayerAddress()!;
        return benchCaps().filter(c => c.owner === turnOwner);
    }

    function selectCap(id: number) {
        if (selectedCapId === id) {
            selectedCapId = null;
            pendingMode = null;
            return;
        }
        selectedCapId = id;
        pendingMode = null;
    }

    function startMove() { if (selectedCapId != null) pendingMode = 'move'; }
    function startAttack() { if (selectedCapId != null) pendingMode = 'attack'; }
    function startPlay() { if (selectedCapId != null) pendingMode = 'play'; }
    function startCapture() { if (selectedCapId != null) pendingMode = 'capture'; }

    function isDeploySpot(x: number, y: number): boolean {
        if (!game) return false;
        const [dx, dy] = game.turnCount % 2 === 0 ? activeLayout.p1Deploy : activeLayout.p2Deploy;
        return x === dx && y === dy;
    }

    function isCellValidTarget(x: number, y: number): boolean {
        if (!selectedCapId || !pendingMode || !game) return false;
        if (!activeLayout.isWalkable(x, y)) return false;

        const target = capAt(x, y);

        if (pendingMode === 'play') {
            return !target && isDeploySpot(x, y);
        }

        const selectedCap = game.caps.find(c => c.id === selectedCapId);
        if (!selectedCap) return false;

        if (pendingMode === 'capture') {
            // Any of my on-board caps can claim; target must be surrounded enemy
            if (selectedCap.x === null) return false;
            if (!target) return false;
            if (isSolo ? target.owner === turnPlayerAddress() : target.owner === account) return false;
            return isSurrounded(game, x, y);
        }

        if (selectedCap.x === null || selectedCap.y === null) return false;

        if (pendingMode === 'move') {
            return !target && isValidStep(game.layout, [selectedCap.x, selectedCap.y], [x, y]);
        }

        if (pendingMode === 'attack') {
            if (!target) return false;
            if (isSolo ? target.owner === turnPlayerAddress() : target.owner === account) return false;
            const dx = Math.abs(selectedCap.x - x);
            const dy = Math.abs(selectedCap.y - y);
            const attackRange = CAP_STATS[selectedCap.capType]?.[2] ?? 1;
            return Math.max(dx, dy) <= attackRange;
        }

        return false;
    }

    function isCaptureTarget(x: number, y: number): boolean {
        if (!game || !selectedCapId || pendingMode !== 'capture') return false;
        return isCellValidTarget(x, y);
    }

    function anySurroundedEnemy(): boolean {
        if (!game) return false;
        const g = game;
        return g.caps.some(c =>
            c.x !== null && c.y !== null &&
            (isSolo ? c.owner !== turnPlayerAddress() : c.owner !== account) &&
            isSurrounded(g, c.x, c.y)
        );
    }

    function onCellClick(x: number, y: number) {
        if (!activeLayout.isWalkable(x, y)) return;

        const target = capAt(x, y);
        if (selectedCapId == null) {
            if (target && isMyCap(target)) {
                selectCap(target.id);
            }
            return;
        }
        if (pendingMode == null) {
            if (target && isMyCap(target)) {
                selectCap(target.id);
            }
            return;
        }

        if (!isCellValidTarget(x, y)) {
            errorMsg = `Invalid ${pendingMode} target at (${x}, ${y})`;
            return;
        }

        const kindMap = {
            move: 'Move',
            attack: 'Attack',
            play: 'Play',
            capture: 'ClaimCapture',
        } as const;
        queuedActions = [...queuedActions, { capId: selectedCapId, kind: kindMap[pendingMode], x, y }];
        status = `Queued ${pendingMode} → (${x},${y})`;
        errorMsg = null;
        pendingMode = null;
        selectedCapId = null;
    }

    function colorFor(c: ChainCap): string {
        if (!game) return '#3b82f6';
        return c.owner === game.player1 ? '#3b82f6' : '#ef4444';
    }

    async function commitTurn() {
        if (!game || queuedActions.length === 0) return;
        errorMsg = null;
        committing = true;
        log(`Submitting ${queuedActions.length} action(s)\u2026`);
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
                <button class="back" onclick={() => { game = null; queuedActions = []; selectedCapId = null; pendingMode = null; }}>← Lobby</button>
                <span class="badge">#{game.id}</span>
                <span class="badge">{activeLayout.name}</span>
                <span class="turn-badge {game.turnCount % 2 === 0 ? 'p1' : 'p2'}">
                    {game.turnCount % 2 === 0 ? "P1's turn" : "P2's turn"}
                </span>
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

            <!-- Board -->
            <div class="board" style="--w:{activeLayout.width};--h:{activeLayout.height}">
                {#each Array.from({ length: activeLayout.height * activeLayout.width }, (_, idx) => idx) as idx}
                    {@const x = idx % activeLayout.width}
                    {@const y = Math.floor(idx / activeLayout.width)}
                    {@const walkable = activeLayout.isWalkable(x, y)}
                    {@const isDeploy = isDeploySpot(x, y)}
                    {@const isValidTarget = isCellValidTarget(x, y)}
                    {@const c = capAt(x, y)}
                    {@const capturable = c ? isSurrounded(game, x, y) && c.owner !== (isSolo ? turnPlayerAddress() : account) : false}
                    <button
                        class="cell"
                        class:walkable={walkable}
                        class:void-cell={!walkable}
                        class:deploy={isDeploy && !c}
                        class:valid-target={isValidTarget}
                        class:capture-target={capturable && pendingMode === 'capture'}
                        class:selected={selectedCapId != null && c?.id === selectedCapId}
                        disabled={!walkable}
                        onclick={() => onCellClick(x, y)}
                    >
                        {#if c}
                            <div class="piece p{c.owner === game.player1 ? '1' : '2'}" class:tower={c.capType === 0}>
                                <div class="type">{c.capType === 0 ? '★' : c.capType}</div>
                                <div class="hp">{c.health}/{c.maxHealth}</div>
                                {#if capturable}<div class="cap-mark">⛓</div>{/if}
                            </div>
                        {:else if isDeploy}
                            <div class="deploy-marker">↓</div>
                        {:else if !walkable}
                            <div class="void-marker">·</div>
                        {/if}
                    </button>
                {/each}
            </div>

            <!-- Action Buttons -->
            {#if selectedCapId != null}
                <div class="actions">
                    {#if capAt(0,0) && false}{/if}
                    <button
                        class:active-mode={pendingMode === 'play'}
                        onclick={startPlay}
                    >Deploy</button>
                    <button
                        class:active-mode={pendingMode === 'move'}
                        onclick={startMove}
                    >Move</button>
                    <button
                        class:active-mode={pendingMode === 'attack'}
                        onclick={startAttack}
                    >Attack</button>
                    {#if anySurroundedEnemy()}
                        <button
                            class="capture-btn"
                            class:active-mode={pendingMode === 'capture'}
                            onclick={startCapture}
                        >⛓ Capture</button>
                    {/if}
                    <button class="cancel" onclick={() => { selectedCapId = null; pendingMode = null; }}>✕</button>
                </div>
                <p class="hint">
                    {#if pendingMode === 'play'}Tap your deploy spot (↓)
                    {:else if pendingMode === 'move'}Tap a highlighted adjacent tile (orthogonal or diagonal)
                    {:else if pendingMode === 'attack'}Tap a highlighted enemy
                    {:else if pendingMode === 'capture'}Tap the chained enemy to send it back to bench
                    {:else}Pick an action, or tap another piece
                    {/if}
                </p>
            {/if}

            <!-- Bench -->
            {#if myBenchCaps().length > 0}
                <div class="bench">
                    <span class="bench-label">Bench ({game.turnCount % 2 === 0 ? 'P1' : 'P2'})</span>
                    <div class="bench-pieces">
                        {#each myBenchCaps() as c}
                            <button
                                class="bench-piece"
                                class:selected={selectedCapId === c.id}
                                onclick={() => { selectedCapId = c.id; pendingMode = 'play'; }}
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
        display: grid;
        grid-template-columns: repeat(var(--w), minmax(0, 1fr));
        grid-template-rows: repeat(var(--h), minmax(0, 1fr));
        gap: 3px;
        background: #1e293b;
        padding: 5px;
        border-radius: 10px;
        aspect-ratio: var(--w) / var(--h);
        max-width: 100%;
    }
    .cell {
        border: 1px solid #334155;
        background: #0f172a;
        border-radius: 6px;
        padding: 0;
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 0;
        min-width: 0;
    }
    .cell.void-cell { opacity: 0.25; border-style: dashed; background: transparent; }
    .cell.walkable { background: #1e293b; }
    .cell.deploy { border: 2px solid #38bdf8; }
    .cell.valid-target { border-color: #22c55e; box-shadow: inset 0 0 8px rgba(34,197,94,0.35); }
    .cell.capture-target { border-color: #a855f7; box-shadow: inset 0 0 8px rgba(168,85,247,0.45); }
    .cell.selected { outline: 2px solid #38bdf8; outline-offset: -2px; }

    .deploy-marker { color: #38bdf8; font-size: clamp(1rem, 5vw, 1.6rem); font-weight: bold; }
    .void-marker { color: #334155; font-size: clamp(0.8rem, 4vw, 1.3rem); }

    .piece {
        width: 100%;
        height: 100%;
        border-radius: 6px;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        position: relative;
    }
    .piece.p1 { background: #2563eb; }
    .piece.p2 { background: #dc2626; }
    .piece.tower { border-radius: 6px 6px 24px 24px; }
    .type { font-size: clamp(0.9rem, 4.5vw, 1.4rem); font-weight: 800; color: #fff; line-height: 1; }
    .hp {
        font-size: clamp(0.55rem, 2.5vw, 0.75rem);
        background: rgba(0,0,0,0.4);
        padding: 0 0.3rem;
        border-radius: 4px;
        color: #fff;
        margin-top: 2px;
    }
    .cap-mark {
        position: absolute;
        top: 1px;
        right: 2px;
        font-size: 0.8rem;
    }

    /* Actions */
    .actions { display: flex; gap: 0.4rem; flex-wrap: wrap; }
    .actions button { flex: 1; min-width: 70px; padding: 0.6rem 0.4rem; font-size: 0.85rem; background: #1e293b; border: 1px solid #334155; }
    .actions button.active-mode { background: #2563eb; border-color: #38bdf8; }
    .actions .capture-btn { background: #4c1d95; border-color: #7c3aed; }
    .actions .capture-btn.active-mode { background: #7c3aed; }
    .actions .cancel { flex: 0 0 auto; background: #475569; }

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
    .bench-piece.selected { outline: 2px solid #c4b5fd; }

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
        .actions button { font-size: 0.78rem; min-width: 58px; }
        .bench-piece { padding: 0.4rem 0.6rem; font-size: 0.78rem; }
    }
</style>