import type { RiskCategory, RiskFactor, RiskReport } from '@memeguard/shared';
import { clsx } from 'clsx';
import { useState } from 'react';
import { LEVEL_HEX, LEVEL_STYLE, RiskBadge, levelForScore } from './RiskBadge';

const CATEGORY_LABEL: Record<RiskCategory, string> = {
  honeypot: 'Honeypot',
  liquidity: 'Liquidity',
  contract: 'Contract',
  concentration: 'Wallet concentration',
  developer: 'Developer',
  market: 'Market integrity',
  data: 'Data quality',
};

const ORDER: RiskCategory[] = [
  'honeypot',
  'liquidity',
  'contract',
  'concentration',
  'developer',
  'market',
  'data',
];

/** Meter: fill carries severity; the track is a lighter step of the same hue. */
export function RugScoreMeter({ score, limit }: { score: number; limit?: number }) {
  const level = levelForScore(score);
  const hex = LEVEL_HEX[level];
  const s = LEVEL_STYLE[level];
  return (
    <div>
      <div className="flex items-end justify-between gap-3">
        <div>
          <div className="text-xs text-muted">RUG_SCORE</div>
          <div className="tabular text-5xl font-semibold leading-none text-ink">{Math.round(score)}</div>
        </div>
        <div className="flex items-center gap-1.5 pb-1 text-sm text-ink">
          <s.Icon size={16} className={s.color} aria-hidden /> {s.label}
        </div>
      </div>
      <div
        className="relative mt-3 h-3 rounded-full"
        style={{ background: `${hex}33` }}
        role="meter"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={score}
        aria-label="Rug score"
      >
        <div
          className="h-3 rounded-full"
          style={{ width: `${Math.min(100, Math.max(0, score))}%`, background: hex }}
        />
        {limit !== undefined && (
          <div
            className="absolute -top-1 h-5 w-0.5 rounded bg-ink"
            style={{ left: `calc(${limit}% - 1px)` }}
            title={`MAX_RUG_SCORE ${limit}`}
          />
        )}
      </div>
      <div className="tabular mt-1 flex justify-between text-[10px] text-muted">
        <span>0</span>
        <span>25</span>
        <span>50</span>
        <span>75</span>
        <span>100</span>
      </div>
      {limit !== undefined && (
        <div className="mt-1 text-xs text-muted">Trading limit (MAX_RUG_SCORE): {limit}</div>
      )}
    </div>
  );
}

export function CategoryBars({ report }: { report: RiskReport }) {
  return (
    <ul className="space-y-2.5">
      {ORDER.map((c) => {
        const a = report.categories[c];
        const hex = LEVEL_HEX[a.level];
        return (
          <li key={c} title={a.explanation}>
            <div className="mb-1 flex items-center justify-between gap-2 text-xs">
              <span className="text-ink-2">{CATEGORY_LABEL[c]}</span>
              <span className="flex items-center gap-2">
                <span className="tabular text-ink">{Math.round(a.score)}</span>
                <RiskBadge level={a.level} compact />
              </span>
            </div>
            <div className="h-2 rounded-full bg-surface-3">
              <div
                className="h-2 rounded-full"
                style={{ width: `${Math.max(1, a.score)}%`, background: hex }}
              />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

function FactorRow({ f }: { f: RiskFactor }) {
  return (
    <li className="rounded-lg border border-border bg-surface-2/50 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-medium text-ink">
          <RiskBadge level={f.severity} compact />
          {f.label}
          {f.critical && (
            <span className="rounded bg-critical/25 px-1.5 text-[10px] font-semibold uppercase tracking-wide text-ink">
              critical
            </span>
          )}
        </div>
        <span className="tabular text-xs text-muted">
          +{Math.round(f.points)} pts · {CATEGORY_LABEL[f.category]}
        </span>
      </div>
      <p className="mt-1.5 text-sm text-ink-2">{f.explanation}</p>
      <div className="mt-1 text-xs text-muted">
        Observed: <span className="text-ink-2">{String(f.observed ?? 'n/a')}</span>
        {f.threshold !== null && f.threshold !== undefined && (
          <>
            {' '}
            · Threshold: <span className="text-ink-2">{String(f.threshold)}</span>
          </>
        )}
        {f.sources.length > 0 && <> · Sources: {f.sources.join(', ')}</>}
      </div>
    </li>
  );
}

export function RiskExplanation({ report }: { report: RiskReport }) {
  const [showAll, setShowAll] = useState(false);
  const factors = [...report.factors].sort(
    (a, b) => Number(b.critical) - Number(a.critical) || b.points - a.points,
  );
  const shown = showAll ? factors : factors.slice(0, 6);
  const outputs: [string, string, string][] = [
    ['RUG_SCORE', String(report.rugScore), report.explanations.rugScore],
    ['HONEYPOT_RISK', report.honeypotRisk, report.explanations.honeypotRisk],
    ['LIQUIDITY_RISK', report.liquidityRisk, report.explanations.liquidityRisk],
    ['CONTRACT_RISK', report.contractRisk, report.explanations.contractRisk],
    [
      'WALLET_CONCENTRATION_RISK',
      report.walletConcentrationRisk,
      report.explanations.walletConcentrationRisk,
    ],
    ['OVERALL_RISK', report.overallRisk, report.explanations.overallRisk],
  ];
  return (
    <div className="space-y-4">
      {report.isLikelyScam && (
        <div
          className="rounded-lg border border-critical/50 bg-critical/15 p-3 text-sm text-ink"
          role="alert"
        >
          <strong>Likely scam / rug pull.</strong>{' '}
          {report.criticalFlags.length > 0 ? `Critical findings: ${report.criticalFlags.join(', ')}.` : ''}{' '}
          The engine will never trade this token.
        </div>
      )}
      <dl className="space-y-2">
        {outputs.map(([k, v, why]) => (
          <div key={k} className="rounded-lg border border-border p-3">
            <dt className="flex items-center justify-between gap-2 text-xs">
              <span className="font-mono text-muted">{k}</span>
              {k === 'RUG_SCORE' ? (
                <span className="tabular font-semibold text-ink">{v}/100</span>
              ) : (
                <RiskBadge level={v as RiskReport['overallRisk']} />
              )}
            </dt>
            <dd className="mt-1.5 text-sm text-ink-2">{why}</dd>
          </div>
        ))}
      </dl>
      <div>
        <h3 className="mb-2 text-sm font-semibold text-ink">Contributing factors ({factors.length})</h3>
        {factors.length === 0 ? (
          <p className="text-sm text-muted">No risk factors triggered.</p>
        ) : (
          <ul className="space-y-2">
            {shown.map((f) => (
              <FactorRow key={f.id} f={f} />
            ))}
          </ul>
        )}
        {factors.length > 6 && (
          <button
            type="button"
            onClick={() => setShowAll((v) => !v)}
            className={clsx('mt-2 text-xs text-series-1 hover:underline')}
          >
            {showAll ? 'Show fewer' : `Show all ${factors.length} factors`}
          </button>
        )}
      </div>
      <div className="text-xs text-muted">
        Model {report.modelVersion} · data completeness {Math.round(report.dataCompleteness * 100)}%
        {report.missingData.length > 0 && ` · missing (treated as risk): ${report.missingData.join(', ')}`}
        {report.llmReview &&
          ` · LLM review: ${report.llmReview.error ? `unavailable (${report.llmReview.error})` : report.llmReview.escalate ? 'escalated' : 'no escalation'}`}
      </div>
    </div>
  );
}
