import type {
  PositionSizing,
  RiskCheckName,
  RiskCheckResult,
  RiskLimits,
  RiskReport,
  Scalar,
  StrategyParams,
  TokenSnapshot,
  TradingMode,
} from '@memeguard/shared';
import { errorMessage } from '../lib/errors';
import { minutesBetween } from '../lib/time';

export interface AccountView {
  /** Conservative equity: open positions at estimated liquidation value. */
  equityUsd: number;
  cashUsd: number;
  peakEquityUsd: number;
  dayStartEquityUsd: number;
  halted: boolean;
  haltReason: string | null;
}

export interface EntryRiskInput {
  mode: TradingMode;
  /** Auto-trading switch (for engine entries) — manual requests bypass it but nothing else. */
  tradingEnabled: boolean;
  liveExecutionSupported: boolean;
  account: AccountView;
  openPositions: number;
  hasOpenPositionForToken: boolean;
  snapshot: TokenSnapshot;
  report: RiskReport;
  sizing: PositionSizing | null;
  limits: RiskLimits;
  strategy: Pick<StrategyParams, 'stopLossPercent'>;
  networkFeeUsd: number;
  llm: { required: boolean; failed: boolean; error: string | null };
  now: Date;
}

export interface RiskEvaluation {
  approved: boolean;
  checks: RiskCheckResult[];
  failed: RiskCheckResult[];
}

type CheckFn = () => { passed: boolean; value: Scalar; limit: Scalar; message: string };

const r2 = (v: number) => Math.round(v * 100) / 100;

/**
 * Hard risk gate. A trade is approved only if EVERY check passes. The design is fail-closed:
 *  - missing inputs (unknown liquidity, age, honeypot status, stale data) fail the check;
 *  - an exception inside any check fails that check;
 *  - an empty check list can never approve (guarded explicitly).
 */
export class RiskManager {
  evaluateEntry(i: EntryRiskInput): RiskEvaluation {
    const checks: RiskCheckResult[] = [];
    const run = (check: RiskCheckName, fn: CheckFn) => {
      try {
        const r = fn();
        checks.push({ check, passed: r.passed === true, value: r.value, limit: r.limit, message: r.message });
      } catch (err) {
        checks.push({ check, passed: false, value: null, limit: null, message: `check error (fail-closed): ${errorMessage(err)}` });
      }
    };
    const L = i.limits;
    const m = i.snapshot.market;
    const size = i.sizing?.sizeUsd ?? null;

    run('TRADING_ENABLED', () => ({
      passed: i.tradingEnabled,
      value: i.tradingEnabled,
      limit: true,
      message: i.tradingEnabled ? 'Trading enabled.' : 'Automatic trading is disabled.',
    }));
    if (i.mode === 'live') {
      run('LIVE_EXECUTION_SUPPORTED', () => ({
        passed: i.liveExecutionSupported,
        value: i.snapshot.chain,
        limit: 'solana',
        message: i.liveExecutionSupported
          ? 'Live execution venue available.'
          : `No live execution venue implemented for ${i.snapshot.chain}.`,
      }));
    }
    run('NOT_HALTED', () => ({
      passed: !i.account.halted,
      value: i.account.halted,
      limit: false,
      message: i.account.halted ? `Trading halted: ${i.account.haltReason ?? 'unknown reason'}.` : 'Not halted.',
    }));
    run('MAX_DAILY_LOSS', () => {
      const start = i.account.dayStartEquityUsd;
      if (!(start > 0)) throw new Error('day-start equity unknown');
      const pnl = i.account.equityUsd - start;
      const floor = -(start * L.maxDailyLossPercent) / 100;
      const worstCase = pnl - (size ?? 0) * (i.strategy.stopLossPercent / 100);
      const passed = pnl > floor && worstCase > floor;
      return {
        passed,
        value: r2(pnl),
        limit: r2(floor),
        message: passed
          ? `Daily P/L $${r2(pnl)} (worst case after this trade $${r2(worstCase)}) above limit $${r2(floor)}.`
          : `Daily loss limit: P/L $${r2(pnl)}, worst case $${r2(worstCase)} vs limit $${r2(floor)}.`,
      };
    });
    run('MAX_DRAWDOWN', () => {
      const peak = i.account.peakEquityUsd;
      if (!(peak > 0)) throw new Error('peak equity unknown');
      const dd = ((peak - i.account.equityUsd) / peak) * 100;
      return {
        passed: dd < L.maxDrawdownPercent,
        value: r2(dd),
        limit: L.maxDrawdownPercent,
        message: `Drawdown ${r2(dd)}% (limit ${L.maxDrawdownPercent}%).`,
      };
    });
    run('MAX_OPEN_POSITIONS', () => ({
      passed: i.openPositions < L.maxOpenPositions,
      value: i.openPositions,
      limit: L.maxOpenPositions,
      message: `${i.openPositions} open positions (max ${L.maxOpenPositions}).`,
    }));
    run('NO_DUPLICATE_POSITION', () => ({
      passed: !i.hasOpenPositionForToken,
      value: i.hasOpenPositionForToken,
      limit: false,
      message: i.hasOpenPositionForToken ? 'A position in this token is already open.' : 'No existing position.',
    }));
    run('MIN_LIQUIDITY', () => {
      const liq = m?.liquidityUsd ?? null;
      if (liq === null) return { passed: false, value: null, limit: L.minLiquidityUsd, message: 'Liquidity unknown (fail-closed).' };
      return {
        passed: liq >= L.minLiquidityUsd,
        value: Math.round(liq),
        limit: L.minLiquidityUsd,
        message: `Pool liquidity $${Math.round(liq)} (min $${L.minLiquidityUsd}).`,
      };
    });
    run('MAX_RUG_SCORE', () => ({
      passed: i.report.rugScore <= L.maxRugScore,
      value: i.report.rugScore,
      limit: L.maxRugScore,
      message: `Rug score ${i.report.rugScore} (max ${L.maxRugScore}).`,
    }));
    run('NO_CRITICAL_FLAGS', () => ({
      passed: !i.report.isLikelyScam && i.report.criticalFlags.length === 0,
      value: i.report.criticalFlags.length,
      limit: 0,
      message:
        i.report.criticalFlags.length > 0
          ? `Critical findings: ${i.report.criticalFlags.join(', ')}.`
          : i.report.isLikelyScam
            ? 'Classified as likely scam.'
            : 'No critical findings.',
    }));
    run('HONEYPOT_VERIFIED', () => {
      const h = i.snapshot.honeypot;
      const verified = h !== null && h.simulated && h.isHoneypot === false && h.sellRouteFound !== false;
      if (!L.requireHoneypotCheck) {
        return {
          passed: h?.isHoneypot !== true,
          value: verified,
          limit: 'optional',
          message: verified ? 'Sell simulation passed.' : 'Honeypot check not required by configuration.',
        };
      }
      return {
        passed: verified,
        value: verified,
        limit: true,
        message: verified
          ? `Sell simulation passed (${h?.source}).`
          : `Sellability not verified${h?.reason ? `: ${h.reason}` : ''} (REQUIRE_HONEYPOT_CHECK).`,
      };
    });
    run('MIN_TOKEN_AGE', () => {
      if (!m?.pairCreatedAt) return { passed: false, value: null, limit: L.minTokenAgeMinutes, message: 'Token age unknown (fail-closed).' };
      const age = minutesBetween(m.pairCreatedAt, i.now);
      return {
        passed: age >= L.minTokenAgeMinutes,
        value: Math.round(age),
        limit: L.minTokenAgeMinutes,
        message: `Token age ${Math.round(age)} min (min ${L.minTokenAgeMinutes} min).`,
      };
    });
    run('DATA_FRESHNESS', () => {
      if (!m) return { passed: false, value: null, limit: L.maxDataAgeSeconds, message: 'No market data.' };
      const age = (i.now.getTime() - Date.parse(m.fetchedAt)) / 1000;
      return {
        passed: Number.isFinite(age) && age <= L.maxDataAgeSeconds,
        value: Math.round(age),
        limit: L.maxDataAgeSeconds,
        message: `Market data is ${Math.round(age)}s old (max ${L.maxDataAgeSeconds}s).`,
      };
    });
    run('MIN_POSITION_SIZE', () => ({
      passed: size !== null && size >= L.minPositionUsd,
      value: size,
      limit: L.minPositionUsd,
      message: size === null ? 'No position size computed.' : `Position size $${r2(size)} (min $${L.minPositionUsd}; limited by ${i.sizing?.limitingFactor}).`,
    }));
    run('MAX_POSITION_PERCENT', () => {
      if (size === null) throw new Error('no size');
      const pct = (size / i.account.equityUsd) * 100;
      return {
        passed: pct <= L.maxPositionPercent + 1e-9,
        value: r2(pct),
        limit: L.maxPositionPercent,
        message: `Position is ${r2(pct)}% of equity (max ${L.maxPositionPercent}%).`,
      };
    });
    run('LIQUIDITY_SHARE', () => {
      if (size === null || !m?.liquidityUsd) throw new Error('size or liquidity unknown');
      const pct = (size / m.liquidityUsd) * 100;
      return {
        passed: pct <= L.maxLiquiditySharePercent + 1e-9,
        value: r2(pct),
        limit: L.maxLiquiditySharePercent,
        message: `Position is ${r2(pct)}% of pool liquidity (max ${L.maxLiquiditySharePercent}%).`,
      };
    });
    run('MAX_SLIPPAGE', () => {
      const slip = i.sizing?.expectedSlippagePct;
      if (slip === undefined || slip === null || !Number.isFinite(slip)) throw new Error('slippage unknown');
      return {
        passed: slip <= L.maxSlippagePercent,
        value: slip,
        limit: L.maxSlippagePercent,
        message: `Expected price impact ${slip}% (max ${L.maxSlippagePercent}%).`,
      };
    });
    run('SUFFICIENT_CASH', () => {
      if (size === null) throw new Error('no size');
      const need = size + 2 * i.networkFeeUsd;
      return {
        passed: need <= i.account.cashUsd,
        value: r2(i.account.cashUsd),
        limit: r2(need),
        message: `Cash $${r2(i.account.cashUsd)} vs required $${r2(need)}.`,
      };
    });
    if (i.llm.required) {
      run('LLM_REVIEW', () => ({
        passed: !i.llm.failed,
        value: !i.llm.failed,
        limit: true,
        message: i.llm.failed ? `Required LLM review unavailable: ${i.llm.error ?? 'unknown'}.` : 'LLM review completed.',
      }));
    }

    const failed = checks.filter((c) => !c.passed);
    return { approved: checks.length > 0 && failed.length === 0, checks, failed };
  }
}
