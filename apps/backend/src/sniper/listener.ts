import { errorMessage } from '../lib/errors';
import type { Logger } from '../lib/logger';
import type { LaunchProgram } from './programs';

/** A pool-creation transaction seen on the log stream, before any parsing. */
export interface LaunchSignal {
  signature: string;
  source: string;
  programId: string;
  slot: number | null;
  /** When this process received the notification (ms since epoch). */
  detectedAt: number;
}

/** The subset of the WHATWG WebSocket API the listener needs (Node 22 ships it globally). */
export interface WebSocketLike {
  onopen: ((ev: unknown) => void) | null;
  onmessage: ((ev: { data: unknown }) => void) | null;
  onclose: ((ev: unknown) => void) | null;
  onerror: ((ev: unknown) => void) | null;
  send(data: string): void;
  close(): void;
}
export type WebSocketFactory = (url: string) => WebSocketLike;

const defaultFactory: WebSocketFactory = (url) => {
  const WS = (globalThis as { WebSocket?: new (u: string) => WebSocketLike }).WebSocket;
  if (!WS) throw new Error('WebSocket is not available in this runtime (Node.js 22+ required)');
  return new WS(url);
};

export interface ListenerStatus {
  connected: boolean;
  reconnects: number;
  lastMessageAt: string | null;
  lastError: string | null;
}

/**
 * Subscribes to `logsSubscribe` for each launch program and emits pool-creation signatures.
 * https://solana.com/docs/rpc/websocket/logssubscribe
 * Reconnects with capped backoff, re-subscribes, drops duplicates and failed transactions, and
 * recycles a connection that has been silent for too long (providers drop idle sockets quietly).
 * The endpoint URL is never logged: it usually embeds the provider's API key.
 */
export class LaunchListener {
  private ws: WebSocketLike | null = null;
  private running = false;
  private connected = false;
  private attempt = 0;
  private reconnects = 0;
  private lastMessageAt: number | null = null;
  private lastError: string | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private watchdog: NodeJS.Timeout | null = null;
  private readonly bySubscription = new Map<number, LaunchProgram>();
  private readonly byRequest = new Map<number, LaunchProgram>();
  private readonly seen = new Set<string>();
  private readonly seenOrder: string[] = [];

  constructor(
    private readonly opts: {
      url: string;
      programs: LaunchProgram[];
      onLaunch: (signal: LaunchSignal) => void;
      logger: Logger;
      wsFactory?: WebSocketFactory;
      idleTimeoutMs?: number;
      now?: () => number;
    },
  ) {}

  private now(): number {
    return this.opts.now?.() ?? Date.now();
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.connect();
    const idle = this.opts.idleTimeoutMs ?? 180_000;
    this.watchdog = setInterval(
      () => {
        if (this.connected && this.lastMessageAt !== null && this.now() - this.lastMessageAt > idle) {
          this.opts.logger.warn('launch stream silent for too long; reconnecting');
          this.ws?.close();
        }
      },
      Math.min(idle, 15_000),
    );
    this.watchdog.unref?.();
  }

  stop(): void {
    this.running = false;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.watchdog) clearInterval(this.watchdog);
    this.reconnectTimer = null;
    this.watchdog = null;
    const ws = this.ws;
    this.ws = null;
    this.connected = false;
    try {
      ws?.close();
    } catch {
      /* already closed */
    }
  }

  status(): ListenerStatus {
    return {
      connected: this.connected,
      reconnects: this.reconnects,
      lastMessageAt: this.lastMessageAt !== null ? new Date(this.lastMessageAt).toISOString() : null,
      lastError: this.lastError,
    };
  }

  private connect(): void {
    if (!this.running) return;
    let ws: WebSocketLike;
    try {
      ws = (this.opts.wsFactory ?? defaultFactory)(this.opts.url);
    } catch (err) {
      this.fail(`could not open launch stream: ${errorMessage(err)}`);
      return;
    }
    this.ws = ws;
    this.bySubscription.clear();
    this.byRequest.clear();
    ws.onopen = () => {
      if (this.ws !== ws) return;
      this.connected = true;
      this.attempt = 0;
      this.lastMessageAt = this.now();
      this.opts.programs.forEach((p, i) => {
        const id = i + 1;
        this.byRequest.set(id, p);
        ws.send(
          JSON.stringify({
            jsonrpc: '2.0',
            id,
            method: 'logsSubscribe',
            params: [{ mentions: [p.programId] }, { commitment: 'confirmed' }],
          }),
        );
      });
      this.opts.logger.info({ programs: this.opts.programs.map((p) => p.name) }, 'launch stream connected');
    };
    ws.onmessage = (ev) => {
      if (this.ws !== ws) return;
      this.lastMessageAt = this.now();
      this.handle(ev.data);
    };
    ws.onerror = () => {
      if (this.ws !== ws) return;
      // The event text can include parts of the endpoint URL (and its API key); keep it generic.
      this.lastError = 'launch stream connection error';
    };
    ws.onclose = () => {
      if (this.ws !== ws) return;
      this.ws = null;
      this.fail(this.lastError ?? 'launch stream closed');
    };
  }

  private fail(reason: string): void {
    this.connected = false;
    this.lastError = reason;
    if (!this.running) return;
    this.attempt += 1;
    this.reconnects += 1;
    const delay = Math.min(30_000, 1000 * 2 ** Math.min(this.attempt - 1, 5));
    this.opts.logger.warn({ reason, retryInMs: delay }, 'launch stream disconnected');
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
    this.reconnectTimer.unref?.();
  }

  private handle(data: unknown): void {
    let msg: {
      id?: number;
      result?: unknown;
      error?: { message?: string };
      method?: string;
      params?: {
        subscription?: number;
        result?: {
          context?: { slot?: number };
          value?: { signature?: string; err?: unknown; logs?: string[] };
        };
      };
    };
    try {
      msg = JSON.parse(typeof data === 'string' ? data : String(data));
    } catch {
      return;
    }
    if (typeof msg.id === 'number') {
      const program = this.byRequest.get(msg.id);
      if (program && typeof msg.result === 'number') this.bySubscription.set(msg.result, program);
      else if (program && msg.error)
        this.lastError = `subscribe ${program.name} failed: ${msg.error.message}`;
      return;
    }
    if (msg.method !== 'logsNotification') return;
    const program = this.bySubscription.get(msg.params?.subscription ?? -1);
    const value = msg.params?.result?.value;
    if (!program || !value?.signature || value.err) return;
    if (!program.marker.test((value.logs ?? []).join('\n'))) return;
    if (this.seen.has(value.signature)) return;
    this.seen.add(value.signature);
    this.seenOrder.push(value.signature);
    if (this.seenOrder.length > 5000) this.seen.delete(this.seenOrder.shift() as string);
    this.opts.onLaunch({
      signature: value.signature,
      source: program.name,
      programId: program.programId,
      slot: msg.params?.result?.context?.slot ?? null,
      detectedAt: this.now(),
    });
  }
}
