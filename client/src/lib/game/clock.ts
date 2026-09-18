import { clockRemaining, type GameClock } from '@caps/game-core/clock';

export interface ClockHold {
    gameId: number;
    turn: number;
    seconds: [number, number];
}

/** Hold a display snapshot while a submitted turn or coherent board update is pending.
 * A hold never changes clock storage or crosses a game/turn boundary. */
export function holdClock(previous: ClockHold | null, clock: GameClock, turn: number, over: boolean, chainNow: number, waiting: boolean): ClockHold | null {
    if (!waiting || over || !clock.enabled) return null;
    if (previous?.gameId === clock.gameId && previous.turn === turn) return previous;
    return {gameId:clock.gameId,turn,seconds:clockRemaining(clock,turn,over,chainNow)!};
}
