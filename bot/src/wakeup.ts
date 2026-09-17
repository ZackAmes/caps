/** Coalesces indexer notifications without losing a notification received during a turn. */
export class Wakeup {
  private pending = false;
  private release: (() => void) | undefined;
  notify() { this.pending = true; this.release?.(); }
  async wait(ms: number, signal: AbortSignal) {
    if (!this.pending && !signal.aborted) {
      await new Promise<void>(resolve => {
        const finish = () => { clearTimeout(timer); signal.removeEventListener('abort', finish); this.release = undefined; resolve(); };
        const timer = setTimeout(finish, ms);
        this.release = finish;
        signal.addEventListener('abort', finish, { once: true });
      });
    }
    this.pending = false;
  }
}
