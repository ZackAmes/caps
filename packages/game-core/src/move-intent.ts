import { encodeActions } from './encode';
import type { ChainGame, TurnAction } from './types';

export const INTENT_LIFETIME_MS = 60000;
export interface MoveIntent {
  identity: string; gameId: number; turn: number; world: string;
  timestamp: number; txHash: string; status: 0 | 1 | 2; actions: TurnAction[];
}
const sameAddress = (a: string, b: string) => BigInt(a) === BigInt(b);
const isFelt = (v: unknown): v is string => typeof v === 'string' && /^0x[\da-f]{1,64}$/i.test(v);
const integer = (v: unknown) => {
  if (typeof v !== 'string' && typeof v !== 'number') throw Error('Invalid integer');
  const n = Number(v); if (!Number.isSafeInteger(n) || n < 0) throw Error('Invalid integer'); return n;
};

/** Reject wrong participants, stale turns, expired hints and malformed action data.
 * The caller also runs previewTurn to check the current game's full action rules. */
export function readMoveIntent(raw: Record<string, unknown>, world: string, game: ChainGame, now = Date.now()): MoveIntent | null {
  try {
    if (game.over || !isFelt(raw.identity) || !isFelt(raw.world) || !isFelt(raw.tx_hash)) return null;
    const gameId = integer(raw.game_id), turn = integer(raw.turn), timestamp = integer(raw.timestamp), status = integer(raw.status);
    if (gameId !== game.id || turn !== game.turnCount || status > 2 || !sameAddress(raw.world, world) ||
        !sameAddress(raw.identity, turn % 2 ? game.player2 : game.player1) ||
        timestamp > now + 5000 || timestamp < now - INTENT_LIFETIME_MS) return null;
    if (!Array.isArray(raw.actions) || raw.actions.length > 129) return null;
    const data = raw.actions.map(integer), actions: TurnAction[] = [];
    let i = 0; const count = data[i++];
    if (count === undefined || count > 32) return null;
    for (let n = 0; n < count; n++) {
      const capId = data[i++], kind = data[i++];
      if (!capId || kind === undefined || kind > 3) return null;
      if (kind === 3) {
        const targetId = data[i++]; if (!targetId) return null;
        actions.push({ capId, kind: 'StackAbility', targetId });
      } else {
        const x = data[i++], y = data[i++];
        if (x === undefined || y === undefined || x > 14 || y > 14) return null;
        actions.push({ capId, kind: (['Play', 'Move', 'Ability'] as const)[kind], x, y });
      }
    }
    if (i !== data.length) return null;
    return { identity: raw.identity, world: raw.world, gameId, turn, timestamp, txHash: raw.tx_hash, status: status as 0 | 1 | 2, actions };
  } catch { return null; }
}

export function intentTypedData(intent: MoveIntent) {
  return {
    types: {
      StarknetDomain: [
        { name: 'name', type: 'shortstring' }, { name: 'version', type: 'shortstring' },
        { name: 'chainId', type: 'shortstring' }, { name: 'revision', type: 'shortstring' },
      ],
      'caps-MoveIntent': [
        { name: 'identity', type: 'ContractAddress' }, { name: 'game_id', type: 'u128' },
        { name: 'turn', type: 'u128' }, { name: 'world', type: 'ContractAddress' },
        { name: 'timestamp', type: 'u128' }, { name: 'tx_hash', type: 'felt' },
        { name: 'status', type: 'u128' }, { name: 'actions', type: 'felt*' },
      ],
    },
    primaryType: 'caps-MoveIntent',
    domain: { name: 'CAPS Move Preview', version: '1', chainId: 'SN_SEPOLIA', revision: '1' as const },
    message: { identity: intent.identity, game_id: String(intent.gameId), turn: String(intent.turn), world: intent.world,
      timestamp: String(intent.timestamp), tx_hash: intent.txHash, status: intent.status, actions: encodeActions(intent.actions).map(String) },
  };
}

// Torii 1.8.16 world.proto: PublishMessageRequest = signature(bytes,1)*,
// message(string,2), world_address(bytes,3). This small unary grpc-web adapter
// shares the existing HTTP endpoint and avoids a second libp2p tunnel or WASM runtime.
const text = new TextEncoder();
const feltBytes = (s: string) => Uint8Array.from(BigInt(s).toString(16).padStart(64, '0').match(/../g)!, h => parseInt(h, 16));
function field(tag: number, value: Uint8Array): number[] {
  const length: number[] = []; let n = value.length;
  do { length.push((n & 127) | (n > 127 ? 128 : 0)); n >>>= 7; } while (n);
  return [tag * 8 + 2, ...length, ...value];
}
export async function publishMoveIntent(endpoint: string, intent: MoveIntent, signature: unknown): Promise<void> {
  const sig = signature as string[] | { r: string; s: string };
  const parts = Array.isArray(sig) ? sig : [sig.r, sig.s];
  if (!parts.length || parts.length > 1024) throw Error('Invalid message signature');
  const data = Uint8Array.from([
    ...parts.flatMap(s => field(1, feltBytes(s))),
    ...field(2, text.encode(JSON.stringify(intentTypedData(intent)))), ...field(3, feltBytes(intent.world)),
  ]);
  const frame = new Uint8Array(data.length + 5);
  new DataView(frame.buffer).setUint32(1, data.length); frame.set(data, 5);
  const response = await fetch(endpoint.replace(/\/$/, '') + '/world.World/PublishMessage', {
    method: 'POST', headers: { 'content-type': 'application/grpc-web+proto', 'x-grpc-web': '1' },
    body: frame, signal: AbortSignal.timeout(3000),
  });
  if (!response.ok) throw Error(`Move relay HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  let status = response.headers.get('grpc-status'), detail = response.headers.get('grpc-message') ?? '', hasData = false;
  for (let i = 0; i + 5 <= bytes.length;) {
    const flag = bytes[i], length = new DataView(bytes.buffer, bytes.byteOffset + i + 1, 4).getUint32(0);
    if (i + 5 + length > bytes.length) throw Error('Truncated relay response');
    const body = bytes.subarray(i + 5, i + 5 + length);
    if (flag & 128) {
      const trailer = new TextDecoder().decode(body);
      status = trailer.match(/grpc-status:\s*(\d+)/i)?.[1] ?? status;
      detail = trailer.match(/grpc-message:[ \t]*([^\r\n]*)/i)?.[1] ?? detail;
    }
    else hasData ||= length > 0;
    i += 5 + length;
  }
  if (status !== '0' || !hasData) throw Error(`Move relay rejected message (${status ?? 'missing status'}): ${detail}`);
}

export interface IntentSigner {
  address: string;
  signMessage(data: ReturnType<typeof intentTypedData>): Promise<unknown>;
}
/** Best effort preview publication never blocks or changes transaction execution. */
export function beginMoveIntent(endpoint: string, world: string, signer: IntentSigner, gameId: number, turn: number, actions: TurnAction[], onError?: (error: unknown) => void) {
  let timestamp = 0, queue = Promise.resolve();
  const send = (status: 0 | 1 | 2, txHash = '0x0') => {
    if (!endpoint) return;
    const intent: MoveIntent = { identity: signer.address, gameId, turn, world, timestamp: timestamp = Math.max(Date.now(), timestamp + 1), status, txHash, actions: actions.map(action => ({...action})) };
    queue = queue.then(async () => {
      const signature = await signer.signMessage(intentTypedData(intent));
      await publishMoveIntent(endpoint, intent, signature);
    }).catch(error => { onError?.(error); });
  };
  send(0);
  return { broadcast: (hash: string) => send(1, hash), cancel: (hash?: string) => send(2, hash), settled: () => queue };
}
