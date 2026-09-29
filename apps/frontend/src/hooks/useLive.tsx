import type { Alert, Decision, ServerEvent, TokenListItem } from '@memeguard/shared';
import { useQueryClient } from '@tanstack/react-query';
import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { subscribeEvents, type ConnectionState } from '../lib/sse';

interface LiveState {
  connection: ConnectionState;
  decisions: Decision[];
  analyzed: TokenListItem[];
  toasts: Alert[];
  dismissToast: (id: number) => void;
}

const LiveContext = createContext<LiveState>({
  connection: 'connecting',
  decisions: [],
  analyzed: [],
  toasts: [],
  dismissToast: () => undefined,
});

/** Which cached queries each server event makes stale. */
const INVALIDATES: Record<ServerEvent['type'], string[][]> = {
  'token.analyzed': [['tokens'], ['token']],
  decision: [['decisions'], ['token']],
  trade: [['trades'], ['performance'], ['positions'], ['sniper']],
  position: [['positions'], ['performance'], ['sniper']],
  alert: [['alerts']],
  performance: [['performance']],
  status: [['status']],
  'sniper.attempt': [['sniper']],
  'social.mention': [['social'], ['tokens']],
};

export function LiveProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient();
  const [connection, setConnection] = useState<ConnectionState>('connecting');
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const [analyzed, setAnalyzed] = useState<TokenListItem[]>([]);
  const [toasts, setToasts] = useState<Alert[]>([]);
  const pending = useRef(new Set<string>());
  const timer = useRef<number | null>(null);

  useEffect(() => {
    // Invalidation is batched so a burst of events triggers one refetch per query.
    const flush = () => {
      for (const key of pending.current) void qc.invalidateQueries({ queryKey: JSON.parse(key) as string[] });
      pending.current.clear();
      timer.current = null;
    };
    const unsubscribe = subscribeEvents((e) => {
      for (const key of INVALIDATES[e.type] ?? []) pending.current.add(JSON.stringify(key));
      if (timer.current === null) timer.current = window.setTimeout(flush, 1500);
      if (e.type === 'decision') setDecisions((d) => [e.data, ...d].slice(0, 60));
      if (e.type === 'token.analyzed') {
        setAnalyzed((list) => [e.data.token, ...list.filter((t) => t.id !== e.data.token.id)].slice(0, 60));
      }
      if (
        e.type === 'alert' &&
        (e.data.severity === 'critical' ||
          ['POSITION_OPENED', 'POSITION_CLOSED', 'STOP_LOSS', 'TAKE_PROFIT', 'SOCIAL_MENTION'].includes(
            e.data.type,
          ))
      ) {
        setToasts((t) => [e.data, ...t].slice(0, 4));
        window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== e.data.id)), 12_000);
      }
    }, setConnection);
    return () => {
      unsubscribe();
      if (timer.current !== null) window.clearTimeout(timer.current);
    };
  }, [qc]);

  return (
    <LiveContext.Provider
      value={{
        connection,
        decisions,
        analyzed,
        toasts,
        dismissToast: (id) => setToasts((t) => t.filter((x) => x.id !== id)),
      }}
    >
      {children}
    </LiveContext.Provider>
  );
}

export const useLive = () => useContext(LiveContext);
