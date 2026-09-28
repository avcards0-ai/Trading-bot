import { describe, expect, it } from 'vitest';
import type { Alert } from '@memeguard/shared';
import { AlertService } from '../../src/alerts/alertService';
import {
  escapeHtml,
  formatDiscord,
  formatTelegram,
  TelegramNotifier,
  type Notifier,
} from '../../src/alerts/notifiers';
import { analysisAlerts, marketAlerts } from '../../src/alerts/rules';
import { computeTradeActivity, computeWalletAnalysis } from '../../src/analysis/activity';
import { RugDetector } from '../../src/analysis/rug/detector';
import { EventBus } from '../../src/lib/events';
import { HttpClient } from '../../src/lib/http';
import { createNullLogger } from '../../src/lib/logger';
import { NOW, cleanContract, cleanSnapshot, market } from '../helpers/snapshots';

describe('trade activity', () => {
  it('detects round-trip (wash) wallets, dominance and uniform sizes', () => {
    const t = (i: number, wallet: string, kind: 'buy' | 'sell', usd: number) => ({
      txHash: `t${i}`,
      wallet,
      kind,
      volumeUsd: usd,
      timestamp: new Date(NOW.getTime() - i * 60_000),
    });
    const trades = Array.from({ length: 40 }, (_, i) => t(i, `W${i % 2}`, i % 2 === 0 ? 'buy' : 'sell', 100));
    const a = computeTradeActivity(trades, 'test')!;
    expect(a.uniqueTraders).toBe(2);
    expect(a.roundTripWallets).toBe(0);
    const washed = computeTradeActivity(
      [...trades, t(99, 'W0', 'sell', 100), t(98, 'W1', 'buy', 100)],
      'test',
    )!;
    expect(washed.roundTripWallets).toBe(2);
    expect(washed.roundTripVolumeShare).toBe(1);
    expect(washed.tradeSizeCv).toBe(0);
    expect(washed.repeatedSizeShare).toBe(1);
  });

  it('returns null without trades', () => expect(computeTradeActivity([], 'x')).toBeNull());
});

describe('wallet clustering', () => {
  it('groups holders funded by the same wallet or by each other', () => {
    const holders = ['A', 'B', 'C', 'D', 'E'].map((address, i) => ({ address, percent: 10 - i }));
    const profiles = new Map([
      [
        'A',
        {
          address: 'A',
          createdAt: new Date(NOW.getTime() - 3_600_000),
          ageIsLowerBound: false,
          fundedBy: 'FUNDER',
        },
      ],
      [
        'B',
        {
          address: 'B',
          createdAt: new Date(NOW.getTime() - 3_600_000),
          ageIsLowerBound: false,
          fundedBy: 'FUNDER',
        },
      ],
      [
        'C',
        {
          address: 'C',
          createdAt: new Date(NOW.getTime() - 3_600_000),
          ageIsLowerBound: false,
          fundedBy: 'A',
        },
      ],
      ['D', { address: 'D', createdAt: new Date('2020-01-01'), ageIsLowerBound: true, fundedBy: null }],
      ['E', { address: 'E', createdAt: new Date('2021-01-01'), ageIsLowerBound: false, fundedBy: 'OTHER' }],
    ]);
    const w = computeWalletAnalysis(holders, profiles, {
      freshWalletAgeHours: 72,
      now: NOW,
      sources: ['t'],
    })!;
    expect(w.clusters).toHaveLength(1);
    expect(w.clusters[0]?.wallets.sort()).toEqual(['A', 'B', 'C']);
    expect(w.clusters[0]?.combinedPercent).toBe(27);
    expect(w.newWallets).toBe(3);
    expect(w.newWalletShare).toBeCloseTo(0.6);
  });
});

describe('alert rules', () => {
  it('raises liquidity crash / removal, extreme drops and volume spikes', () => {
    const prev = market();
    const types = (m: ReturnType<typeof market>) => marketAlerts(prev, m).map((a) => a.type);
    expect(types(market({ liquidityUsd: 60_000 }))).toContain('LIQUIDITY_CRASH');
    expect(types(market({ liquidityUsd: 100_000 }))).toContain('LIQUIDITY_REMOVAL');
    expect(types(market({ priceUsd: 0.0005 }))).toContain('EXTREME_PRICE_DROP');
    expect(types(market({ volumeUsd: { m5: 80_000, h1: 90_000, h6: 1, h24: 1 } }))).toContain(
      'ABNORMAL_VOLUME',
    );
    expect(marketAlerts(prev, market())).toEqual([]);
  });

  it('raises developer selling, tax changes, contract changes and rug-risk escalation', () => {
    const det = new RugDetector();
    const prev = cleanSnapshot();
    const cur = cleanSnapshot({
      contract: cleanContract({ sellTaxPct: 15, codeHash: 'hash-2', mintAuthority: 'NEW' }),
      developer: {
        sources: ['rpc'],
        devAddress: 'DEV1',
        lookbackMinutes: 60,
        transfersOut: 0,
        sells: 1,
        percentOfSupplyMoved: 6,
        transfersToFreshWallets: 0,
        events: [
          {
            kind: 'sell',
            signature: 'sig1',
            timestamp: NOW.toISOString(),
            percentOfSupply: 6,
            counterparty: null,
          },
        ],
      },
    });
    const alerts = analysisAlerts(
      { market: prev.market, snapshot: prev, report: det.analyze(prev, { now: NOW }) },
      { market: cur.market, snapshot: cur, report: det.analyze(cur, { now: NOW, previous: prev }) },
    ).map((a) => a.type);
    expect(alerts).toEqual(
      expect.arrayContaining([
        'DEVELOPER_SELLING',
        'MASSIVE_TRANSFER',
        'TAX_CHANGE',
        'CONTRACT_CHANGE',
        'RUG_RISK_ESCALATION',
      ]),
    );
  });
});

class MemoryAlertsRepo {
  rows: (Record<string, unknown> & { id: number })[] = [];
  async insert(v: Record<string, unknown>) {
    const row = {
      id: this.rows.length + 1,
      acknowledged: false,
      deliveredTo: [],
      createdAt: new Date(),
      data: {},
      tokenId: null,
      ...v,
    };
    this.rows.push(row as never);
    return row;
  }
  async existsSince(key: string, since: Date) {
    return this.rows.some((r) => r.dedupeKey === key && (r.createdAt as Date) >= since);
  }
  async setDelivered(id: number, channels: string[]) {
    const r = this.rows.find((x) => x.id === id);
    if (r) r.deliveredTo = channels;
  }
}

describe('AlertService', () => {
  const make = (
    opts: Partial<{
      minSeverity: 'info' | 'warning' | 'critical';
      cooldownSeconds: number;
      maxPerTypePerHour: number;
    }> = {},
  ) => {
    const sent: Alert[] = [];
    const notifier: Notifier = { name: 'mock', send: async (a) => void sent.push(a) };
    const repo = new MemoryAlertsRepo();
    const bus = new EventBus();
    const streamed: string[] = [];
    bus.subscribe((e) => streamed.push(e.type));
    const svc = new AlertService(
      repo as never,
      bus,
      [notifier],
      { minSeverity: 'warning', cooldownSeconds: 600, maxPerTypePerHour: 2, ...opts },
      createNullLogger(),
    );
    return { svc, sent, repo, streamed };
  };
  const input = {
    type: 'LIQUIDITY_CRASH' as const,
    severity: 'critical' as const,
    title: 'x',
    message: 'y',
    tokenId: 1,
  };

  it('persists, streams and notifies; deduplicates within the cooldown', async () => {
    const { svc, sent, repo, streamed } = make();
    expect(await svc.raise(input)).not.toBeNull();
    expect(await svc.raise(input)).toBeNull();
    await svc.flush();
    expect(repo.rows).toHaveLength(1);
    expect(sent).toHaveLength(1);
    expect(streamed).toEqual(['alert']);
    expect(repo.rows[0]?.deliveredTo).toEqual(['mock']);
  });

  it('respects the minimum severity but always pushes trade lifecycle events', async () => {
    const { svc, sent } = make({ cooldownSeconds: 0 });
    await svc.raise({ ...input, type: 'ABNORMAL_VOLUME', severity: 'info' });
    await svc.raise({ ...input, type: 'POSITION_OPENED', severity: 'info' });
    await svc.flush();
    expect(sent.map((a) => a.type)).toEqual(['POSITION_OPENED']);
  });

  it('caps external notifications per type per hour (alerts are still stored)', async () => {
    const { svc, sent, repo } = make({ cooldownSeconds: 0, maxPerTypePerHour: 2 });
    for (let i = 0; i < 5; i++) await svc.raise({ ...input, dedupeKey: `k${i}` });
    await svc.flush();
    expect(repo.rows).toHaveLength(5);
    expect(sent).toHaveLength(2);
  });

  it('never fails the caller when a notifier throws', async () => {
    const repo = new MemoryAlertsRepo();
    const svc = new AlertService(
      repo as never,
      new EventBus(),
      [
        {
          name: 'broken',
          send: async () => {
            throw new Error('down');
          },
        },
      ],
      { minSeverity: 'info', cooldownSeconds: 0, maxPerTypePerHour: 10 },
      createNullLogger(),
    );
    await expect(svc.raise(input)).resolves.not.toBeNull();
    await svc.flush();
    expect(svc.notifierStatus([{ name: 'broken', configured: true }])[0]).toMatchObject({
      sent: 0,
      failed: 1,
    });
  });
});

describe('notifiers', () => {
  const alert: Alert = {
    id: 1,
    tokenId: 1,
    chain: 'solana',
    address: 'MINT',
    symbol: '<b>X</b>',
    type: 'STOP_LOSS',
    severity: 'critical',
    title: 'Stop & loss',
    message: 'Price < stop',
    data: { pnl: -5, nested: { a: 1 } },
    acknowledged: false,
    deliveredTo: [],
    createdAt: NOW.toISOString(),
  };

  it('escapes HTML for Telegram', () => {
    const text = formatTelegram(alert, null);
    expect(text).toContain('&lt;b&gt;X&lt;/b&gt;');
    expect(text).toContain('Stop &amp; loss');
    expect(escapeHtml('<>&')).toBe('&lt;&gt;&amp;');
  });

  it('builds a Discord embed without pinging anyone', () => {
    const body = formatDiscord(alert) as {
      embeds: { color: number; fields: { name: string }[] }[];
      allowed_mentions: { parse: string[] };
    };
    expect(body.allowed_mentions.parse).toEqual([]);
    expect(body.embeds[0]?.color).toBe(0xef4444);
    expect(body.embeds[0]?.fields.map((f) => f.name)).toContain('pnl');
  });

  it('posts to the Telegram Bot API path with the chat id', async () => {
    const calls: { url: string; body: string }[] = [];
    const client = new HttpClient({
      name: 'telegram',
      baseUrl: 'https://api.telegram.org',
      ratePerMinute: 600,
      fetchImpl: async (url, init) => {
        calls.push({ url, body: String(init?.body) });
        return new Response('{"ok":true}', { status: 200 });
      },
    });
    await new TelegramNotifier(client, '123:TOKEN', '-100').send(alert);
    expect(calls[0]?.url).toBe('https://api.telegram.org/bot123:TOKEN/sendMessage');
    expect(JSON.parse(calls[0]?.body ?? '{}')).toMatchObject({ chat_id: '-100', parse_mode: 'HTML' });
  });
});
