import type { ServerEvent } from '@memeguard/shared';
import { API_BASE, authHeaders } from './api';

export type ConnectionState = 'connecting' | 'open' | 'closed';

/**
 * Server-Sent Events over fetch (so the Authorization header can be sent — EventSource cannot
 * set headers, and API keys must never go into URLs). Reconnects with capped backoff.
 */
export function subscribeEvents(
  onEvent: (e: ServerEvent) => void,
  onState: (s: ConnectionState) => void,
): () => void {
  let stopped = false;
  let controller: AbortController | null = null;
  let attempt = 0;

  const parseBlock = (block: string) => {
    let type = 'message';
    const data: string[] = [];
    for (const line of block.split('\n')) {
      if (line.startsWith(':')) continue;
      if (line.startsWith('event:')) type = line.slice(6).trim();
      else if (line.startsWith('data:')) data.push(line.slice(5).trimStart());
    }
    if (data.length === 0) return;
    try {
      onEvent({ type, data: JSON.parse(data.join('\n')) } as ServerEvent);
    } catch {
      /* malformed event: ignore */
    }
  };

  const run = async () => {
    while (!stopped) {
      onState('connecting');
      controller = new AbortController();
      try {
        const res = await fetch(`${API_BASE}/events`, { headers: authHeaders(), signal: controller.signal });
        if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);
        onState('open');
        attempt = 0;
        const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
        let buffer = '';
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += value;
          let idx = buffer.indexOf('\n\n');
          while (idx >= 0) {
            parseBlock(buffer.slice(0, idx));
            buffer = buffer.slice(idx + 2);
            idx = buffer.indexOf('\n\n');
          }
        }
      } catch {
        /* network error or abort: fall through to reconnect */
      }
      if (stopped) break;
      onState('closed');
      attempt += 1;
      await new Promise((r) => setTimeout(r, Math.min(15_000, 1000 * 2 ** Math.min(attempt, 4))));
    }
  };
  void run();
  return () => {
    stopped = true;
    controller?.abort();
  };
}
