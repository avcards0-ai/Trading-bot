import { EventEmitter } from 'node:events';
import type { ServerEvent } from '@memeguard/shared';

/** In-process pub/sub for real-time dashboard updates (fanned out over SSE). */
export class EventBus {
  private readonly emitter = new EventEmitter();

  constructor() {
    this.emitter.setMaxListeners(200);
  }

  publish(event: ServerEvent): void {
    this.emitter.emit('event', event);
  }

  subscribe(fn: (event: ServerEvent) => void): () => void {
    this.emitter.on('event', fn);
    return () => this.emitter.off('event', fn);
  }

  get listenerCount(): number {
    return this.emitter.listenerCount('event');
  }
}
