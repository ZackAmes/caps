import { decodeBoard } from '@caps/game-core/published-board';
import { decodeClock, clockRemaining } from '@caps/game-core/clock';
import { CallData, type Account, type RpcProvider } from 'starknet';
import { decodeGame, decodeHand, decodeCapType, decodeStack } from '@caps/game-core/decode';
import { beginMoveIntent } from '@caps/game-core/move-intent';
import { encodeActions } from '@caps/game-core/encode';
import { getLayout, type LayoutConfig } from '@caps/game-core/board';
import type { ChainGame, ChainHand, CapTypeDef, TurnAction, AbilityStack } from '@caps/game-core/types';
import type { GameAdapter, GameInfo } from '../ports';

export interface PositionV7 {
  game: ChainGame;
  hand: ChainHand;
  definitions: Map<number, CapTypeDef>;
  layout: LayoutConfig;
  stack: AbilityStack;
}

/** All ABI and rules-version assumptions live here, outside the polling worker. */
export class CapsV7Adapter implements GameAdapter<ChainGame, PositionV7, TurnAction> {
  private boards = new Map<string, LayoutConfig>();
  private definitions = new Map<string, CapTypeDef>();
  private pendingIntents = new Map<string, ReturnType<typeof beginMoveIntent>>();
  constructor(private provider: RpcProvider, private account: Account, private actionsAddress: string, private boardsAddress: string, private toriiUrl = '', private worldAddress = '0x0') {}

  private call(entrypoint: string, calldata: (string | number)[] = []) {
    return this.provider.callContract({ contractAddress: this.actionsAddress, entrypoint, calldata: CallData.compile(calldata) });
  }

  async checkCompatibility() {
    const [version] = await this.call('rules_version');
    if (Number(version) !== 7) throw new Error(`Unsupported CAPS rules version ${Number(version)}; add an adapter before running this bot.`);
    await this.gameCount(); // The deployment must also expose the discovery endpoint.
  }

  async gameCount() { return Number((await this.call('get_game_count'))[0]); }

  async readGame(id: number): Promise<GameInfo<ChainGame> | null> {
    const game = decodeGame(await this.call('get_game', [id]));
    return game ? { id: game.id, turn: game.turnCount, over: game.over, players: [game.player1, game.player2], state: game } : null;
  }

  async prepare(info: GameInfo<ChainGame>): Promise<PositionV7> {
    const game = info.state;
    if (game.setId !== 0) throw new Error(`Reference strategy does not support set ${game.setId}`);
    let layout: LayoutConfig;
    if (game.layout === 255) {
      const address = this.boardsAddress;
      if (!address) throw new Error('Board registry missing from manifest');
      const [id] = await this.call('get_game_board', [game.id]);
      let cached = this.boards.get(id);
      if (!cached) {
        const board = decodeBoard(await this.provider.callContract({contractAddress:address,entrypoint:'get_board',calldata:[id]}));
        if (!board) throw new Error('Game board missing');
        cached = board.layout; this.boards.set(id,cached);
      }
      layout = cached;
    } else layout = getLayout(game.layout);
    const hand = decodeHand(await this.call('get_hand', [game.id, game.turnCount % 2]));
    if (!hand) throw new Error('Missing hand');
    const definitions = new Map<number, CapTypeDef>();
    for (const type of new Set(game.caps.map(c => c.capType))) {
      const key = `${game.setId}:${type}`;
      let def = this.definitions.get(key);
      if (!def) {
        def = decodeCapType(await this.call('get_cap_data', [game.id, type])) ?? undefined;
        if (!def) throw new Error(`Missing definition for piece ${type}`);
        this.definitions.set(key, def);
      }
      definitions.set(type, def);
    }
    return { game, hand, definitions, layout, stack: decodeStack(await this.call('get_stack', [game.id])) };
  }

  async sendTurn(game: GameInfo<ChainGame>, actions: TurnAction[]): Promise<string> {
    const intent = beginMoveIntent(this.toriiUrl, this.worldAddress, this.account, game.id, game.turn, actions,
      error => console.warn('Move preview unavailable', String(error)));
    try {
      const response = await this.account.execute({
        contractAddress: this.actionsAddress,
        entrypoint: 'take_turn_if_current',
        calldata: CallData.compile([game.id, game.turn, ...encodeActions(actions)]),
      }, { tip: 0 });
      intent.broadcast(response.transaction_hash);
      if (this.pendingIntents.size >= 256) this.pendingIntents.delete(this.pendingIntents.keys().next().value!);
      this.pendingIntents.set(response.transaction_hash, intent);
      return response.transaction_hash;
    } catch (error) { intent.cancel(); throw error; }
  }

  async claimTimeout(game: GameInfo<ChainGame>): Promise<string | null> {
    const clock = decodeClock(await this.call('get_clock', [game.id]));
    const times = clockRemaining(clock, game.turn, game.over);
    if (!times || times[game.turn % 2] > 0) return null;
    const response = await this.account.execute({
      contractAddress: this.actionsAddress, entrypoint: 'claim_timeout',
      calldata: CallData.compile([game.id, game.turn]),
    }, { tip: 0 });
    return response.transaction_hash;
  }

  async transactionStatus(hash: string): Promise<'pending' | 'succeeded' | 'reverted'> {
    try {
      const receipt = await this.provider.getTransactionReceipt(hash);
      if (receipt.isReverted()) {
        this.pendingIntents.get(hash)?.cancel(hash); this.pendingIntents.delete(hash);
        return 'reverted';
      }
      if (receipt.isSuccess() && ['ACCEPTED_ON_L2', 'ACCEPTED_ON_L1'].includes(receipt.finality_status)) {
        this.pendingIntents.delete(hash); return 'succeeded';
      }
      return 'pending';
    } catch (error) {
      // A just-broadcast hash may not have propagated; other RPC failures must surface.
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === 29) return 'pending';
      throw error;
    }
  }
}
