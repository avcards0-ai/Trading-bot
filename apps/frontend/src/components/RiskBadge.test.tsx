import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { RiskReport } from '@memeguard/shared';
import { CategoryBars, RugScoreMeter } from './RugRiskPanel';
import { RiskBadge, levelForScore } from './RiskBadge';

describe('risk visuals', () => {
  it('always renders a text label (never color alone)', () => {
    const { container } = render(
      <>
        <RiskBadge level="LOW" />
        <RiskBadge level="MEDIUM" />
        <RiskBadge level="HIGH" />
        <RiskBadge level="CRITICAL" />
      </>,
    );
    for (const l of ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']) expect(screen.getByText(l)).toBeInTheDocument();
    // Each badge carries its own icon.
    expect(container.querySelectorAll('svg')).toHaveLength(4);
  });

  it('maps rug scores to levels at the documented thresholds', () => {
    expect(levelForScore(0)).toBe('LOW');
    expect(levelForScore(25)).toBe('MEDIUM');
    expect(levelForScore(50)).toBe('HIGH');
    expect(levelForScore(75)).toBe('CRITICAL');
  });

  it('exposes the rug score as an accessible meter with the trading limit', () => {
    render(<RugScoreMeter score={42} limit={35} />);
    const meter = screen.getByRole('meter', { name: 'Rug score' });
    expect(meter).toHaveAttribute('aria-valuenow', '42');
    expect(screen.getByText(/MAX_RUG_SCORE\): 35/)).toBeInTheDocument();
  });

  it('renders every risk category with its level', () => {
    const cat = (category: string, score: number, level: string) => ({
      category,
      score,
      level,
      explanation: `${category} why`,
      factorIds: [],
    });
    const report = {
      categories: {
        honeypot: cat('honeypot', 0, 'LOW'),
        liquidity: cat('liquidity', 60, 'HIGH'),
        contract: cat('contract', 30, 'MEDIUM'),
        concentration: cat('concentration', 80, 'CRITICAL'),
        developer: cat('developer', 0, 'LOW'),
        market: cat('market', 0, 'LOW'),
        data: cat('data', 0, 'LOW'),
      },
    } as unknown as RiskReport;
    render(<CategoryBars report={report} />);
    expect(screen.getByText('Wallet concentration')).toBeInTheDocument();
    expect(screen.getAllByText('Critical')).toHaveLength(1);
    expect(screen.getAllByText('High')).toHaveLength(1);
  });
});
