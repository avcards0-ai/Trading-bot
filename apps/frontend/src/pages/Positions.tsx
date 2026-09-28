import type { Position } from '@memeguard/shared';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { PositionsTable, TradesTable } from '../components/tables';
import { Button, Card, ErrorBox, Spinner } from '../components/ui';
import { api } from '../lib/api';

export function PositionsPage() {
  const qc = useQueryClient();
  const [page, setPage] = useState(0);
  const open = useQuery({ queryKey: ['positions', 'open'], queryFn: () => api.positions('open'), refetchInterval: 15_000 });
  const closed = useQuery({ queryKey: ['positions', 'closed'], queryFn: () => api.positions('closed') });
  const trades = useQuery({ queryKey: ['trades', page], queryFn: () => api.trades(50, page * 50), placeholderData: keepPreviousData });
  const [busy, setBusy] = useState<number | null>(null);
  const close = useMutation({
    mutationFn: (p: Position) => api.closePosition(p.id),
    onMutate: (p) => setBusy(p.id),
    onSettled: () => {
      setBusy(null);
      void qc.invalidateQueries({ queryKey: ['positions'] });
      void qc.invalidateQueries({ queryKey: ['trades'] });
      void qc.invalidateQueries({ queryKey: ['performance'] });
    },
  });

  return (
    <div className="space-y-5">
      <h1 className="text-lg font-semibold">Positions & trade history</h1>
      {close.error && <ErrorBox error={close.error} />}
      <Card
        title="Open positions"
        subtitle="Monitored continuously: stop loss, take profit, trailing stop, max hold time, liquidity pulls and rug-risk escalation all trigger automatic exits"
        padded={false}
      >
        {open.isLoading ? (
          <Spinner />
        ) : (
          <PositionsTable
            items={open.data?.items ?? []}
            busyId={busy}
            onClose={(p) => {
              if (window.confirm(`Close ${p.symbol ?? p.address} at market (${p.mode})?`)) close.mutate(p);
            }}
          />
        )}
      </Card>
      <Card title="Closed positions" padded={false}>
        {closed.isLoading ? <Spinner /> : <PositionsTable items={closed.data?.items ?? []} />}
      </Card>
      <Card title={trades.data ? `Trade history (${trades.data.total})` : 'Trade history'} subtitle="Every order attempt, including failed and reverted transactions" padded={false}>
        {trades.isLoading ? <Spinner /> : <TradesTable items={trades.data?.items ?? []} />}
      </Card>
      <div className="flex justify-end gap-2">
        <Button disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
          Previous
        </Button>
        <Button disabled={!trades.data || (page + 1) * 50 >= trades.data.total} onClick={() => setPage((p) => p + 1)}>
          Next
        </Button>
      </div>
    </div>
  );
}
