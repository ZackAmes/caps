<script lang="ts">
    import { onMount } from 'svelte';
    import {
        connect, isConnected, getAccount, createGame, takeTurn, getGame,
        type ChainGame, type ChainCap, type TurnAction, CAP_STATS,
    } from '$lib/dojo/client';

    let account = $state<string | null>(null);
    let status = $state<string>('Disconnected');
    let errorMsg = $state<string | null>(null);

    let opponent = $state('');
    let gameIdInput = $state('1');
    let game: ChainGame | null = $state(null);

    // Turn editor
    let selectedCapId = $state<number | null>(null);
    let pendingMode = $state<'move' | 'attack' | 'play' | null>(null);
    let queuedActions: TurnAction[] = $state([]);
    let committing = $state(false);

    const W = 3;
    const H = 7;

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
            const acc = getAccount();
            // create_game needs the connected account as p1; opponent input is p2.
            const opp = opponent.trim();
            if (!opp) throw new Error('Enter an opponent address');
            await createGame(opp);
            status = 'Game created';
            // refresh games listing via get_game using current counter
            await refreshGames();
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        }
    }

    async function refreshGames() {
        // simplest: try to load the requested game id
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
            status = `Loaded game ${id}`;
        } catch (e: any) {
            errorMsg = e?.message ?? String(e);
        }
    }

    function myAddress(): string | null {
        return account;
    }

    function isMyCap(c: ChainCap): boolean {
        return account !== null && c.owner === account;
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
        return game?.caps.filter(c => c.x === null) ?? [];
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

    function onCellClick(x: number, y: number) {
        const target = capAt(x, y);
        if (selectedCapId == null) {
            // select a friendly cap on this cell, or a bench cap
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
        // queue an action for the selected cap toward (x,y)
        if (target && isMyCap(target) && target.id !== selectedCapId) return;
        // Move/Attack to friendly-only cells handled by contract; Play can target empty
        const kindMap = { move: 'Move', attack: 'Attack', play: 'Play' } as const;
        queuedActions = [...queuedActions, { capId: selectedCapId, kind: kindMap[pendingMode], x, y }];
        status = `Queued ${pendingMode} → (${x},${y})`;
        pendingMode = null;
        selectedCapId = null;
    }

    function colorFor(c: ChainCap): string {
        const palette = ['#ff6b6b', '#4ecdc4', '#ffe66d', '#a8e6cf'];
        const base = palette[(c.capType % palette.length + palette.length) % palette.length];
        return account && c.owner === account ? base : '#9aa0a6';
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
    <h1>Caps</h1>

    <div class="toolbar">
        {#if !account}
            <button onclick={handleConnect}>Connect Wallet</button>
        {:else}
            <span class="addr" title={account}>{account.slice(0, 6)}…{account.slice(-4)}</span>
            <button onclick={handleConnect}>Reconnect</button>
        {/if}
    </div>

    <div class="actions-row">
        <input bind:value={opponent} placeholder="Opponent address (p2)" />
        <button onclick={handleCreate} disabled={!account}>Create Game</button>
        <input bind:value={gameIdInput} type="number" placeholder="Game id" />
        <button onclick={handleLoad} disabled={!account}>Load</button>
    </div>

    {#if errorMsg}
        <div class="error">{errorMsg}</div>
    {/if}
    <div class="status">Status: {status}</div>

    {#if game}
        <div class="meta">
            <span>Game #{game.id}</span>
            <span>Turn {game.turnCount}</span>
            <span>{game.over ? (game.winner === '0' ? 'Draw' : 'Game over') : ''}</span>
            {#if isMyTurn()}<span class="yourturn">Your turn</span>{/if}
        </div>

        {#if selectedCapId != null}
            <div class="edit">
                Selected cap #{selectedCapId}
                <button onclick={startPlay}>Play</button>
                <button onclick={startMove}>Move</button>
                <button onclick={startAttack}>Attack</button>
                <span>then tap a cell</span>
            </div>
        {/if}

        <div class="board" style="--w:{W};--h:{H}">
            {#each Array.from({ length: H * W }, (_, idx) => idx) as idx}
                {@const x = idx % W}
                {@const y = Math.floor(idx / W)}
                {@const c = capAt(x, y)}
                <button
                    class="cell"
                    class:selected={selectedCapId != null && c?.id === selectedCapId}
                    class:highlight={selectedCapId != null}
                    onclick={() => onCellClick(x, y)}
                >
                    {#if c}
                        <div class="piece" style="background:{colorFor(c)}">
                            <div class="type">{c.capType === 0 ? '★' : c.capType}</div>
                            <div class="hp">{c.health}/{c.maxHealth}</div>
                        </div>
                    {/if}
                </button>
            {/each}
        </div>

        {#if benchCaps().length > 0}
            <div class="bench">
                <span>Bench:</span>
                {#each benchCaps() as c}
                    <button
                        class="bench-piece"
                        class:selected={selectedCapId === c.id}
                        onclick={() => { selectedCapId = c.id; pendingMode = 'play'; }}
                    >#{c.id} t{c.capType} {c.health}hp</button>
                {/each}
            </div>
        {/if}

        <button class="commit" onclick={commitTurn} disabled={queuedActions.length === 0 || committing}>
            Submit Turn ({queuedActions.length})
        </button>
    {/if}
</div>

<style>
    .wrap { font-family: system-ui, sans-serif; padding: 1rem; max-width: 420px; margin: 0 auto; }
    h1 { margin: 0 0 1rem; }
    .toolbar, .actions-row, .meta, .edit, .bench { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; margin-bottom: 0.5rem; }
    input { padding: 0.4rem; border: 1px solid #ccc; border-radius: 6px; }
    button { padding: 0.4rem 0.8rem; border: none; border-radius: 6px; background: #1976d2; color: #fff; cursor: pointer; }
    button:disabled { opacity: 0.5; cursor: not-allowed; }
    .addr { font-family: monospace; background: #eee; padding: 0.2rem 0.4rem; border-radius: 4px; }
    .error { color: #c62828; margin-bottom: 0.5rem; }
    .status { color: #555; margin-bottom: 0.5rem; }
    .yourturn { color: #2e7d32; font-weight: 600; }
    .edit { background: #e3f2fd; padding: 0.4rem; border-radius: 6px; }
    .board {
        display: grid;
        grid-template-columns: repeat(var(--w), 60px);
        grid-template-rows: repeat(var(--h), 60px);
        gap: 2px;
        margin: 1rem 0;
    }
    .cell { width: 60px; height: 60px; border: 1px solid #ddd; background: #fafafa; padding: 2px; border-radius: 4px; }
    .cell.highlight { border-color: #90caf9; }
    .cell.selected { border-color: #1976d2; }
    .piece { width: 100%; height: 100%; border-radius: 6px; display: flex; flex-direction: column; align-items: center; justify-content: center; color: #fff; }
    .type { font-size: 1.1rem; font-weight: 700; }
    .hp { font-size: 0.7rem; background: rgba(0,0,0,0.3); padding: 0 0.3rem; border-radius: 4px; }
    .bench { margin-bottom: 1rem; }
    .bench-piece { background: #6a1b9a; }
    .bench-piece.selected { outline: 2px solid #000; }
    .commit { background: #2e7d32; padding: 0.6rem 1.2rem; font-size: 1rem; }
</style>
