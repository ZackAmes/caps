/** Torii is an update signal; callers still validate coherent state through RPC.
 * Keeping this adapter separate lets us switch indexers without changing game rules. */
export interface GameUpdate {
  id: number;
  turn: number;
  over: boolean;
  players: [string, string];
}
export type IndexerStatus = 'connecting' | 'live' | 'offline';
export interface WatchOptions {
  gameId?: number;
  onGame: (game: GameUpdate) => void;
  onIntent?: (model: Record<string, unknown>) => void;
  onStatus?: (status: IndexerStatus) => void;
}
const query = (intents: boolean) => `subscription {
  entityUpdated {
    models { ... on caps_Game { id turn_count over player1 player2 }
      ${intents ? "... on caps_MoveIntent { identity game_id turn world timestamp tx_hash status actions }" : ""}
    }
  }
}`;

export function watchGames(endpoint: string, options: WatchOptions): () => void {
  if (!endpoint) { options.onStatus?.('offline'); return () => {}; }
  let url: URL;
  try { url = new URL(endpoint); } catch { options.onStatus?.('offline'); return () => {}; }
  if (!['http:', 'https:', 'ws:', 'wss:'].includes(url.protocol)) { options.onStatus?.('offline'); return () => {}; }
  url.protocol = ['https:', 'wss:'].includes(url.protocol) ? 'wss:' : 'ws:';
  url.pathname = url.pathname.replace(/\/(graphql(?:\/ws)?)?$/, '') + '/graphql/ws';
  url.hash = '';
  const seen = new Map<number, string>();
  let stopped = false, socket: WebSocket | undefined, retryMs = 1000;
  let reconnect: ReturnType<typeof setTimeout> | undefined;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let status: IndexerStatus | undefined;
  const report = (next: IndexerStatus) => {
    if (!stopped && next !== status) { status = next; options.onStatus?.(next); }
  };
  function connect() {
    if (stopped) return;
    report('connecting');
    const ws = socket = new WebSocket(url, 'graphql-transport-ws');
    let lastMessage = Date.now(), acknowledged = false;
    ws.onopen = () => ws.send(JSON.stringify({ type: 'connection_init' }));
    ws.onmessage = event => {
      if (stopped || socket !== ws) return;
      lastMessage = Date.now();
      try {
        const message = JSON.parse(String(event.data));
        if (message.type === 'connection_ack') {
          acknowledged = true; seen.clear();
          ws.send(JSON.stringify({ id: 'games', type: 'subscribe', payload: { query: query(!!options.onIntent) } }));
          report('live');
        } else if (message.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong', payload: message.payload }));
        } else if (message.type === 'pong') {
          retryMs = 1000;
        } else if (message.type === 'error' || message.type === 'complete' || message.payload?.errors?.length) {
          ws.close();
        } else if (message.type === 'next') {
          retryMs = 1000;
          for (const model of message.payload?.data?.entityUpdated?.models ?? []) {
            if (model.identity && (options.gameId === undefined || Number(model.game_id) === options.gameId)) options.onIntent?.(model);
            const id = Number(model.id), turn = Number(model.turn_count);
            if (!Number.isSafeInteger(id) || id < 1 || !Number.isSafeInteger(turn) || turn < 0 ||
                typeof model.over !== 'boolean' || ![model.player1, model.player2].every(p => typeof p === 'string' && /^0x[0-9a-f]+$/i.test(p))) continue;
            if (options.gameId !== undefined && id !== options.gameId) continue;
            const version = `${turn}:${model.over}:${model.player1}:${model.player2}`;
            if (seen.get(id) === version) continue;
            if (seen.size >= 256) seen.delete(seen.keys().next().value!);
            seen.set(id, version);
            options.onGame({ id, turn, over: model.over, players: [model.player1, model.player2] });
          }
        }
      } catch { ws.close(); }
    };
    ws.onerror = () => ws.close();
    ws.onclose = () => {
      clearInterval(heartbeat);
      if (stopped || socket !== ws) return;
      report('offline');
      reconnect = setTimeout(connect, retryMs);
      retryMs = Math.min(retryMs * 2, 30000);
    };
    heartbeat = setInterval(() => {
      if (Date.now() - lastMessage > (acknowledged ? 45000 : 10000)) { ws.close(); return; }
      if (acknowledged && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }));
    }, 5000);
  }
  connect();
  return () => { stopped = true; clearTimeout(reconnect); clearInterval(heartbeat); socket?.close(); };
}
