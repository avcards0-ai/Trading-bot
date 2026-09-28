import { describe, expect, it } from 'vitest';
import { age, pct, price, ratio, shortAddr, usd } from './format';

describe('formatters', () => {
  it('formats USD with sign and compact notation', () => {
    expect(usd(1234.5)).toBe('$1,234.50');
    expect(usd(-12)).toBe('−$12.00');
    expect(usd(5, { sign: true })).toBe('+$5.00');
    expect(usd(2_500_000, { compact: true })).toBe('$2.5M');
    expect(usd(null)).toBe('—');
  });

  it('formats meme-coin prices with a subscript zero count', () => {
    expect(price(0.00000123)).toBe('$0.0₅123');
    expect(price(0.0123)).toBe('$0.01230');
    expect(price(1.5)).toBe('$1.5');
    expect(price(Number.NaN)).toBe('—');
  });

  it('formats percents, ratios and addresses', () => {
    expect(pct(12.345, { sign: true })).toBe('+12.3%');
    expect(pct(-3)).toBe('−3.0%');
    expect(ratio(1.5)).toBe('1.50×');
    expect(shortAddr('So11111111111111111111111111111111111111112')).toBe('So1111…1112');
  });

  it('formats ages', () => {
    expect(age(new Date(Date.now() - 5 * 60_000).toISOString())).toBe('5m');
    expect(age(new Date(Date.now() - 125 * 60_000).toISOString())).toBe('2h 5m');
  });
});
