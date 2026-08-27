<script lang="ts">
    import { onMount } from 'svelte';
    import {
        connect, isConnected, getAccount, createGame, createSoloGame, takeTurn, getGame,
        getLayout, isValidStep, LAYOUTS, LAYOUT_PERIMETER_5X5, LAYOUT_CROSS_5X5,
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
    let pendingMode = $state<'move' | 'attack' | 'play' | null>(null);
    let queuedActions: TurnAction[] = $state([]);
    let committing = $state(false);

    let activeLayout = $derived<LayoutConfig>(getLayout(game ? game.layout : selectedLayout));

    async function handleConnect() {
        errorMsg = null;
        try {
            const acc = await connect();
            account = acc.address;
            status = 'Connected';
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        }
    }

    async function handleCreate() {
        errorMsg = null;
        try {
            const opp = opponent.trim();
            if (!opp) throw new Error('Enter an opponent address');
            await createGame(opp, selectedLayout);
            status = 'Game created';
            await refreshGames();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        }
    }

    async function handleCreateSolo() {
        errorMsg = null;
        try {
            await createSoloGame(selectedLayout);
            status = `Solo game created with ${activeLayout.name}`;
            await refreshGames();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        }
    }

    async function refreshGames() {
        const id = Number(gameIdInput);
        if (!Number.isNaN(id) && id > 0) {
            await handleLoad();
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
            status = `Loaded game #${id} (${getLayout(game.layout).name})`;
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        }
    }

    function isMyCap(c: ChainCap): boolean {
        if (!account || !game) return false;
        if (game.player1 === game.player2 && game.player1 === account) {
            const currentTurnPlayer = game.turnCount % 2 === 0 ? game.player1 : game.player2;
            return c.owner === currentTurnPlayer;
        }
        return c.owner === account;
    }

    function isMyTurn(): boolean {
        if (!game || !account) return false;
        const turnPlayer = game.turnCount % 2 === 0 ? game.player1 : game.player2;
        return turnPlayer === account;
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
        const turnOwner = game.turnCount % 2 === 0 ? game.player1 : game.player2;
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

    function startMove() {
        if (selectedCapId == null) return;
        pendingMode = 'move';
    }
    function startAttack() {
        if (selectedCapId == null) return;
        pendingMode = 'attack';
    }
    function startPlay() {
        if (selectedCapId == null) return;
        pendingMode = 'play';
    }

    function isDeploySpot(x: number, y: number): boolean {
        if (!game) return false;
        const isP1 = game.turnCount % 2 === 0;
        const [dx, dy] = isP1 ? activeLayout.p1Deploy : activeLayout.p2Deploy;
        return x === dx && y === dy;
    }

    function isCellValidTarget(x: number, y: number): boolean {
        if (!selectedCapId || !pendingMode || !game) return false;
        if (!activeLayout.isWalkable(x, y)) return false;

        const target = capAt(x, y);

        if (pendingMode === 'play') {
            // Must be unoccupied and at deploy spot
            return !target && isDeploySpot(x, y);
        }

        const selectedCap = game.caps.find(c => c.id === selectedCapId);
        if (!selectedCap || selectedCap.x === null || selectedCap.y === null) return false;

        if (pendingMode === 'move') {
            // Must be unoccupied and valid 1-step (including diagonal)
            return !target && isValidStep(game.layout, [selectedCap.x, selectedCap.y], [x, y]);
        }

        if (pendingMode === 'attack') {
            // Must be occupied by opponent
            if (!target) return false;
            const isFriendly = game.player1 === game.player2
                ? target.owner === selectedCap.owner
                : target.owner === account;
            if (isFriendly) return false;
            const dx = Math.abs(selectedCap.x - x);
            const dy = Math.abs(selectedCap.y - y);
            const chebyshevDist = Math.max(dx, dy);
            const attackRange = CAP_STATS[selectedCap.capType]?.[2] ?? 1;
            return chebyshevDist <= attackRange;
        }

        return false;
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

        // Validate before queueing
        if (!isCellValidTarget(x, y)) {
            errorMsg = `Invalid ${pendingMode} target at (${x}, ${y})`;
            return;
        }

        const kindMap = { move: 'Move', attack: 'Attack', play: 'Play' } as const;
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
        try {
            await takeTurn(game.id, queuedActions);
            queuedActions = [];
            status = 'Turn submitted';
            await handleLoad();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        } finally {
            committing = false;
        }
    }

    onMount(() => {});
</script>

<div class="wrap">
    <h1>Caps — Tactical Board</h1>

    <div class="toolbar">
        {#if !account}
            <button onclick={handleConnect}>Connect Controller</button>
        {:else}
            <span class="addr" title={account}>{account.slice(0, 6)}…{account.slice(-4)}</span>
            <button onclick={handleConnect}>Reconnect</button>
        {/if}
    </div>

    <!-- Layout Picker -->
    <div class="layout-picker">
        <label for="layout-select">Layout:</label>
        <select id="layout-select" bind:value={selectedLayout}>
            {#each Object.values(LAYOUTS) as l}
                <option value={l.id}>{l.name}</option>
            {/each}
        </select>
    </div>

    <div class="actions-row">
        <button onclick={handleCreateSolo} disabled={!account}>Self-Play Game</button>
        <div class="or">or</div>
        <input bind:value={opponent} placeholder="Opponent address (p2)" />
        <button onclick={handleCreate} disabled={!account}>Create vs P2</button>
    </div>

    <div class="load-row">
        <input bind:value={gameIdInput} type="number" placeholder="Game id" />
        <button onclick={handleLoad} disabled={!account}>Load Game</button>
    </div>

    {#if errorMsg}
        <div class="error">{errorMsg}</div>
    {/if}
    <div class="status">Status: {status}</div>

    {#if game}
        <div class="meta">
            <span>Game #{game.id}</span>
            <span class="layout-tag">{activeLayout.name}</span>
            <span>Turn {game.turnCount} ({game.turnCount % 2 === 0 ? 'P1 Blue' : 'P2 Red'})</span>
            <span>{game.over ? (game.winner === '0' ? 'Draw' : `Winner: ${game.winner.slice(0, 6)}…`) : ''}</span>
            {#if isMyTurn()}<span class="yourturn">Active Turn</span>{/if}
        </div>

        {#if selectedCapId != null}
            <div class="edit">
                Selected cap #{selectedCapId}
                <button onclick={startPlay} class:active-mode={pendingMode === 'play'}>Deploy</button>
                <button onclick={startMove} class:active-mode={pendingMode === 'move'}>Move (1-step/diag)</button>
                <button onclick={startAttack} class:active-mode={pendingMode === 'attack'}>Attack</button>
                <button class="cancel-btn" onclick={() => { selectedCapId = null; pendingMode = null; }}>Cancel</button>
            </div>
        {/if}

        <div class="board" style="--w:{activeLayout.width};--h:{activeLayout.height}">
            {#each Array.from({ length: activeLayout.height * activeLayout.width }, (_, idx) => idx) as idx}
                {@const x = idx % activeLayout.width}
                {@const y = Math.floor(idx / activeLayout.width)}
                {@const walkable = activeLayout.isWalkable(x, y)}
                {@const isDeploy = isDeploySpot(x, y)}
                {@const isValidTarget = isCellValidTarget(x, y)}
                {@const c = capAt(x, y)}
                <button
                    class="cell"
                    class:walkable={walkable}
                    class:void-cell={!walkable}
                    class:deploy={isDeploy && !c}
                    class:valid-target={isValidTarget}
                    class:selected={selectedCapId != null && c?.id === selectedCapId}
                    disabled={!walkable}
                    onclick={() => onCellClick(x, y)}
                >
                    {#if c}
                        <div class="piece" style="background:{colorFor(c)}">
                            <div class="type">{c.capType === 0 ? '★' : c.capType}</div>
                            <div class="hp">{c.health}/{c.maxHealth}</div>
                        </div>
                    {:else if isDeploy}
                        <div class="deploy-marker">↓</div>
                    {:else if !walkable}
                        <div class="void-marker">·</div>
                    {/if}
                </button>
            {/each}
        </div>

        {#if myBenchCaps().length > 0}
            <div class="bench">
                <span>Bench ({game.turnCount % 2 === 0 ? 'P1' : 'P2'}):</span>
                {#each myBenchCaps() as c}
                    <button
                        class="bench-piece"
                        class:selected={selectedCapId === c.id}
                        onclick={() => { selectedCapId = c.id; pendingMode = 'play'; }}
                    >#{c.id} {c.capType === 0 ? '★ Tower' : `Type ${c.capType}`} ({c.health}hp)</button>
                {/each}
            </div>
        {/if}

        <button class="commit" onclick={commitTurn} disabled={queuedActions.length === 0 || committing}>
            Submit Turn ({queuedActions.length} action{queuedActions.length === 1 ? '' : 's'})
        </button>
    {/if}
</div>

<style>
    .wrap { font-family: system-ui, sans-serif; padding: 1rem; max-width: 440px; margin: 0 auto; color: #1e293b; }
    h1 { margin: 0 0 1rem; font-size: 1.5rem; }
    .toolbar, .layout-picker, .actions-row, .load-row, .meta, .edit, .bench { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; margin-bottom: 0.5rem; }
    .layout-picker label { font-size: 0.9rem; font-weight: 600; color: #475569; }
    .layout-picker select { padding: 0.35rem 0.6rem; border: 1px solid #cbd5e1; border-radius: 6px; background: #fff; font-size: 0.85rem; }
    .or { color: #94a3b8; font-size: 0.85rem; }
    input { padding: 0.4rem; border: 1px solid #cbd5e1; border-radius: 6px; }
    button { padding: 0.4rem 0.8rem; border: none; border-radius: 6px; background: #2563eb; color: #fff; cursor: pointer; font-weight: 500; }
    button:disabled { opacity: 0.5; cursor: not-allowed; }
    .addr { font-family: monospace; background: #f1f5f9; padding: 0.2rem 0.4rem; border-radius: 4px; border: 1px solid #e2e8f0; }
    .error { color: #dc2626; margin-bottom: 0.5rem; font-size: 0.9rem; }
    .status { color: #64748b; margin-bottom: 0.5rem; font-size: 0.9rem; }
    .yourturn { color: #16a34a; font-weight: 600; }
    .layout-tag { background: #f1f5f9; border: 1px solid #cbd5e1; padding: 0.1rem 0.4rem; border-radius: 4px; font-size: 0.8rem; }
    .edit { background: #eff6ff; padding: 0.5rem; border-radius: 6px; border: 1px solid #bfdbfe; font-size: 0.9rem; }
    .active-mode { background: #1d4ed8; outline: 2px solid #93c5fd; }
    .cancel-btn { background: #64748b; }
    .board {
        display: grid;
        grid-template-columns: repeat(var(--w), 64px);
        grid-template-rows: repeat(var(--h), 64px);
        gap: 3px;
        margin: 1rem 0;
        background: #e2e8f0;
        padding: 6px;
        border-radius: 8px;
    }
    .cell { width: 64px; height: 64px; border: 1px solid #cbd5e1; background: #ffffff; padding: 2px; border-radius: 4px; position: relative; }
    .cell.void-cell { background: #f8fafc; border: 1px dashed #e2e8f0; opacity: 0.4; }
    .cell.walkable { background: #ffffff; border-color: #94a3b8; }
    .cell.deploy { border: 2px solid #3b82f6; background: #f0f9ff; }
    .cell.valid-target { border-color: #22c55e; background: #f0fdf4; box-shadow: inset 0 0 6px #86efac; cursor: pointer; }
    .cell.selected { border-color: #2563eb; outline: 2px solid #2563eb; }
    .deploy-marker { color: #3b82f6; font-weight: bold; font-size: 1.2rem; display: flex; align-items: center; justify-content: center; height: 100%; }
    .void-marker { color: #cbd5e1; font-size: 1.5rem; display: flex; align-items: center; justify-content: center; height: 100%; }
    .piece { width: 100%; height: 100%; border-radius: 6px; display: flex; flex-direction: column; align-items: center; justify-content: center; color: #fff; }
    .type { font-size: 1.1rem; font-weight: 700; }
    .hp { font-size: 0.7rem; background: rgba(0,0,0,0.35); padding: 0 0.3rem; border-radius: 4px; }
    .bench { margin-bottom: 1rem; }
    .bench-piece { background: #7c3aed; font-size: 0.85rem; }
    .bench-piece.selected { outline: 2px solid #1e1b4b; }
    .commit { background: #16a34a; padding: 0.6rem 1.2rem; font-size: 1rem; width: 100%; }
</style>
