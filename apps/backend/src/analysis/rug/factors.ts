import type { RiskCategory, RiskFactor, RiskLevel, Scalar, TokenSnapshot } from '@memeguard/shared';
import { circulatingHolders } from '../activity';
import { pctChange } from '../../lib/math';

export interface RiskContext {
  now: Date;
  previous: TokenSnapshot | null;
  freshWalletAgeHours: number;
}

export const levelFromScore = (score: number): RiskLevel =>
  score >= 75 ? 'CRITICAL' : score >= 50 ? 'HIGH' : score >= 25 ? 'MEDIUM' : 'LOW';

const fmtPct = (v: number, d = 1) => `${v.toFixed(d)}%`;
const fmtUsd = (v: number) =>
  v >= 1_000_000
    ? `$${(v / 1_000_000).toFixed(2)}M`
    : v >= 1_000
      ? `$${(v / 1_000).toFixed(1)}k`
      : `$${v.toFixed(0)}`;
const short = (a: string | null) =>
  a && a.length > 12 ? `${a.slice(0, 6)}…${a.slice(-4)}` : (a ?? 'unknown');

class FactorList {
  readonly items: RiskFactor[] = [];
  constructor(private readonly category: RiskCategory) {}

  add(
    id: string,
    label: string,
    points: number,
    observed: Scalar,
    threshold: Scalar,
    explanation: string,
    sources: string[],
    critical = false,
  ): void {
    const p = Math.max(0, Math.min(100, points));
    if (p <= 0 && !critical) return;
    this.items.push({
      id,
      category: this.category,
      label,
      points: p,
      severity: critical ? 'CRITICAL' : levelFromScore(p),
      critical,
      observed,
      threshold,
      explanation,
      sources,
    });
  }
}

const srcs = (...xs: (string[] | string | null | undefined)[]): string[] => [
  ...new Set(xs.flatMap((x) => (Array.isArray(x) ? x : x ? [x] : []))),
];

// ---------------------------------------------------------------------------
// HONEYPOT: can holders actually sell, and at what cost?
// ---------------------------------------------------------------------------
export function honeypotFactors(s: TokenSnapshot, ctx: RiskContext): RiskFactor[] {
  const f = new FactorList('honeypot');
  const c = s.contract;
  const h = s.honeypot;
  const cs = c?.sources ?? [];
  const hs = h ? [h.source] : [];
  const renounced = c?.ownershipRenounced === true;

  if (h?.isHoneypot === true) {
    f.add(
      'honeypot_confirmed',
      'Honeypot confirmed by simulation',
      100,
      true,
      false,
      `A buy/sell simulation failed to sell the token${h.reason ? `: ${h.reason}` : ''}. Buyers would be unable to exit.`,
      hs,
      true,
    );
  }
  if (c?.flaggedHoneypot === true) {
    f.add(
      'honeypot_flagged',
      'Security provider flags honeypot',
      95,
      true,
      false,
      'A security scanner classifies this contract as a honeypot (sells blocked or confiscatory).',
      cs,
      true,
    );
  }
  if (h?.sellRouteFound === false) {
    f.add(
      'no_sell_route',
      'No route to sell',
      95,
      false,
      true,
      'The token can be bought but no aggregator route exists to sell it back.',
      hs,
      true,
    );
  }
  if (c?.nonTransferable === true) {
    f.add(
      'non_transferable',
      'Non-transferable token',
      100,
      true,
      false,
      'The mint has the Token-2022 non-transferable extension: tokens can never be sold.',
      cs,
      true,
    );
  }
  if (c?.defaultAccountStateFrozen === true) {
    f.add(
      'default_frozen',
      'New token accounts frozen by default',
      90,
      true,
      false,
      'New holder accounts start frozen; only the freeze authority can thaw them, so buyers may be unable to sell.',
      cs,
      true,
    );
  }
  if (c?.cannotSellAll === true) {
    f.add(
      'cannot_sell_all',
      'Cannot sell entire balance',
      70,
      true,
      false,
      'The contract prevents holders from selling their full balance.',
      cs,
    );
  }
  if (c?.cannotBuy === true) {
    f.add(
      'cannot_buy',
      'Buying restricted',
      40,
      true,
      false,
      'The contract currently blocks or restricts buys.',
      cs,
    );
  }

  const sellTax = maxOf(c?.sellTaxPct, h?.sellTaxPct);
  if (sellTax !== null) {
    const pts = sellTax >= 50 ? 95 : sellTax >= 25 ? 70 : sellTax >= 10 ? 45 : sellTax >= 5 ? 20 : 0;
    f.add(
      'sell_tax',
      'Sell tax',
      pts,
      round1(sellTax),
      10,
      `Selling costs ${fmtPct(sellTax)} in token tax${sellTax >= 50 ? ' — effectively a honeypot' : ''}.`,
      srcs(cs, hs),
      sellTax >= 50,
    );
  }
  const buyTax = maxOf(c?.buyTaxPct, h?.buyTaxPct);
  if (buyTax !== null) {
    const pts = buyTax >= 50 ? 75 : buyTax >= 25 ? 55 : buyTax >= 10 ? 35 : buyTax >= 5 ? 15 : 0;
    f.add(
      'buy_tax',
      'Buy tax',
      pts,
      round1(buyTax),
      10,
      `Buying costs ${fmtPct(buyTax)} in token tax.`,
      srcs(cs, hs),
    );
  }
  const transferTax = maxOf(c?.transferTaxPct, h?.transferTaxPct);
  if (transferTax !== null) {
    const pts = transferTax >= 10 ? 50 : transferTax >= 3 ? 25 : transferTax > 0 ? 10 : 0;
    f.add(
      'transfer_tax',
      'Transfer tax',
      pts,
      round1(transferTax),
      3,
      `Every transfer is taxed ${fmtPct(transferTax)}.`,
      srcs(cs, hs),
    );
  }
  if (c?.taxModifiable === true) {
    f.add(
      'tax_modifiable',
      'Taxes can be changed',
      renounced ? 15 : 45,
      true,
      false,
      renounced
        ? 'Tax setter exists but ownership appears renounced.'
        : 'The owner can raise buy/sell taxes at any time (hidden-tax / soft-honeypot risk).',
      cs,
    );
  }
  if (c?.personalTaxModifiable === true) {
    f.add(
      'personal_tax',
      'Per-wallet tax can be set',
      60,
      true,
      false,
      'The owner can assign a punitive tax to specific wallets, trapping chosen holders.',
      cs,
    );
  }
  if (c?.hasBlacklist === true) {
    f.add(
      'blacklist',
      'Blacklist function',
      renounced ? 15 : 45,
      true,
      false,
      renounced
        ? 'Blacklist functions exist but ownership appears renounced.'
        : 'The owner can blacklist wallets, blocking them from selling.',
      cs,
    );
  }
  if (c?.hasWhitelist === true) {
    f.add(
      'whitelist',
      'Whitelist function',
      30,
      true,
      false,
      'Trading may be restricted to whitelisted wallets.',
      cs,
    );
  }
  if (c?.transferPausable === true) {
    f.add(
      'pausable',
      'Transfers can be paused',
      renounced ? 20 : 55,
      true,
      false,
      'An authority can pause all transfers, freezing every holder.',
      cs,
    );
  }
  if (c?.tradingCooldown === true) {
    f.add(
      'cooldown',
      'Trading cooldown',
      25,
      true,
      false,
      'Cooldowns limit how quickly holders can sell.',
      cs,
    );
  }
  if (c?.freezable === true) {
    f.add(
      'freeze_authority',
      'Freeze authority active',
      70,
      short(c.freezeAuthority),
      null,
      `Freeze authority ${short(c.freezeAuthority)} can freeze any holder's token account, preventing sells.`,
      cs,
    );
  }
  if (c?.transferHook === true) {
    f.add(
      'transfer_hook',
      'Transfer hook program',
      55,
      true,
      false,
      'A custom program executes on every transfer and can reject sells.',
      cs,
    );
  }
  const verified = h !== null && h.simulated && h.isHoneypot !== null;
  if (!verified) {
    f.add(
      'honeypot_unverified',
      'Sellability not verified',
      35,
      false,
      true,
      `No successful sell simulation was available${h?.reason ? ` (${h.reason})` : ''}. Treated as elevated risk (fail-closed).`,
      hs,
    );
  }
  // History: tax changes
  const prev = ctx.previous;
  if (prev) {
    const prevSell = maxOf(prev.contract?.sellTaxPct, prev.honeypot?.sellTaxPct);
    if (prevSell !== null && sellTax !== null && Math.abs(sellTax - prevSell) >= 2) {
      f.add(
        'tax_changed',
        'Sell tax changed',
        sellTax > prevSell ? 55 : 20,
        round1(sellTax),
        round1(prevSell),
        `Sell tax changed from ${fmtPct(prevSell)} to ${fmtPct(sellTax)} since the previous analysis.`,
        srcs(cs, hs),
      );
    }
  }
  return f.items;
}

// ---------------------------------------------------------------------------
// CONTRACT: privileged control, upgradeability, verifiability
// ---------------------------------------------------------------------------
export function contractFactors(s: TokenSnapshot, ctx: RiskContext): RiskFactor[] {
  const f = new FactorList('contract');
  const c = s.contract;
  const cs = c?.sources ?? [];
  const isSolana = s.chain === 'solana';
  const renounced = c?.ownershipRenounced === true;

  for (const w of s.warnings) {
    if (['no_code', 'mint_not_found', 'not_a_mint', 'unknown_token_program'].includes(w.code)) {
      f.add(`warning_${w.code}`, 'Invalid token contract', 100, w.code, null, w.message, [w.source], true);
    }
    if (w.code === 'fake_token' || w.code === 'airdrop_scam') {
      f.add(
        `warning_${w.code}`,
        w.code === 'fake_token' ? 'Impersonation token' : 'Airdrop scam',
        95,
        true,
        false,
        w.message,
        [w.source],
        true,
      );
    }
  }
  if (!c) {
    f.add(
      'contract_unknown',
      'Contract data unavailable',
      50,
      null,
      null,
      'No contract/security source returned data, so privileged controls (mint, freeze, blacklist, upgradeability) cannot be ruled out.',
      [],
    );
    return f.items;
  }

  if (!isSolana) {
    if (c.isVerified === false) {
      f.add(
        'unverified',
        'Source not verified',
        50,
        false,
        true,
        'Contract source code is not verified, so its behaviour cannot be audited.',
        cs,
      );
    } else if (c.isVerified === null) {
      f.add(
        'verification_unknown',
        'Verification unknown',
        20,
        null,
        true,
        'Contract verification status could not be determined.',
        cs,
      );
    }
    if (c.ownershipRenounced === false) {
      f.add(
        'owner_active',
        'Active owner',
        25,
        short(c.ownerAddress),
        'renounced',
        `Owner ${short(c.ownerAddress)} retains privileged control over the contract.`,
        cs,
      );
    }
  }
  if (c.isProxy === true) {
    f.add(
      'upgradeable',
      'Upgradeable proxy',
      55,
      c.proxyImplementation ? short(c.proxyImplementation) : true,
      false,
      'The token is an upgradeable proxy: its logic can be replaced at any time (e.g. to block sells or mint).',
      cs,
    );
  }
  if (c.mintable === true) {
    const pts = isSolana ? 65 : renounced ? 15 : 60;
    f.add(
      'mint_authority',
      isSolana ? 'Mint authority active' : 'Mintable supply',
      pts,
      isSolana ? short(c.mintAuthority) : true,
      isSolana ? 'revoked' : false,
      isSolana
        ? `Mint authority ${short(c.mintAuthority)} can create unlimited new tokens and dump them on holders.`
        : renounced
          ? 'A mint function exists but ownership appears renounced.'
          : 'The owner can mint new tokens, diluting holders.',
      cs,
    );
  }
  if (c.hiddenOwner === true) {
    f.add(
      'hidden_owner',
      'Hidden owner',
      85,
      true,
      false,
      'The contract has a hidden owner that keeps control even if ownership looks renounced.',
      cs,
      true,
    );
  }
  if (c.canTakeBackOwnership === true) {
    f.add(
      'reclaim_ownership',
      'Ownership can be reclaimed',
      80,
      true,
      false,
      'Renounced ownership can be taken back — a classic fake-renounce trick.',
      cs,
      true,
    );
  }
  if (c.ownerCanChangeBalance === true) {
    f.add(
      'balance_control',
      isSolana ? 'Permanent delegate' : 'Owner can change balances',
      95,
      true,
      false,
      isSolana
        ? `Permanent delegate ${short(c.permanentDelegate)} can move or burn tokens from any holder.`
        : 'The owner can modify any holder’s balance.',
      cs,
      true,
    );
  }
  if (c.selfDestruct === true) {
    f.add(
      'selfdestruct',
      'Self-destruct',
      45,
      true,
      false,
      'Contract can self-destruct (heuristic bytecode finding).',
      cs,
    );
  }
  if (c.externalCall === true) {
    f.add(
      'external_call',
      'External calls in transfer',
      25,
      true,
      false,
      'Transfers call external contracts whose behaviour can change.',
      cs,
    );
  }
  const fnCount = c.suspiciousFunctions.length;
  if (fnCount > 0) {
    f.add(
      'suspicious_functions',
      'Suspicious functions',
      Math.min(50, 15 + fnCount * 8),
      fnCount,
      0,
      `Privileged functions detected: ${c.suspiciousFunctions.slice(0, 6).join(', ')}${fnCount > 6 ? ', …' : ''}.`,
      cs,
    );
  }
  if (c.metadataMutable === true && isSolana) {
    f.add(
      'metadata_mutable',
      'Mutable metadata',
      10,
      true,
      false,
      'Token name/symbol/image can be changed (spoofing risk).',
      cs,
    );
  }
  const prev = ctx.previous?.contract;
  if (prev?.codeHash && c.codeHash && prev.codeHash !== c.codeHash) {
    f.add(
      'code_changed',
      'Contract / authorities changed',
      70,
      'changed',
      'unchanged',
      'Contract code, implementation or mint authorities changed since the previous analysis.',
      cs,
    );
  }
  if (
    prev?.ownerAddress !== undefined &&
    prev?.ownerAddress !== null &&
    c.ownerAddress !== prev.ownerAddress
  ) {
    f.add(
      'owner_changed',
      'Owner changed',
      50,
      short(c.ownerAddress),
      short(prev.ownerAddress),
      `Ownership moved from ${short(prev.ownerAddress)} to ${short(c.ownerAddress)}.`,
      cs,
    );
  }
  return f.items;
}

// ---------------------------------------------------------------------------
// LIQUIDITY: can the liquidity be pulled, and is it deep enough to exit?
// ---------------------------------------------------------------------------
export function liquidityFactors(s: TokenSnapshot, ctx: RiskContext): RiskFactor[] {
  const f = new FactorList('liquidity');
  const l = s.liquidity;
  const m = s.market;
  const ls = srcs(l?.sources, m?.source);
  const liq = l?.totalLiquidityUsd ?? m?.liquidityUsd ?? null;

  if (s.reportedRugged === true) {
    f.add(
      'reported_rugged',
      'Already rugged',
      100,
      true,
      false,
      'A security provider reports this token has already been rugged.',
      ls,
      true,
    );
  }
  if (liq === null) {
    f.add(
      'liquidity_unknown',
      'Liquidity unknown',
      60,
      null,
      null,
      'Pool liquidity could not be determined.',
      ls,
    );
  } else {
    const pts = liq < 1_000 ? 95 : liq < 5_000 ? 75 : liq < 20_000 ? 50 : liq < 50_000 ? 25 : 0;
    f.add(
      'liquidity_amount',
      'Low liquidity',
      pts,
      Math.round(liq),
      50_000,
      `Pool liquidity is only ${fmtUsd(liq)}; small sells move the price sharply and exits may be impossible.`,
      ls,
      liq < 1_000,
    );
  }
  if (l && !l.programControlled) {
    const locked = l.lpLockedPercent;
    const burned = l.lpBurnedPercent;
    if (locked === null && burned === null) {
      f.add(
        'lp_lock_unknown',
        'LP lock unverifiable',
        35,
        null,
        90,
        'Could not verify whether LP tokens are locked or burned; assumed withdrawable.',
        ls,
      );
    } else {
      const secured = Math.min(100, (locked ?? 0) + (burned ?? 0));
      const pts = secured < 50 ? 70 : secured < 90 ? 40 : 0;
      f.add(
        'lp_unlocked',
        'LP not locked/burned',
        pts,
        round1(secured),
        90,
        `Only ${fmtPct(secured)} of LP tokens are locked or burned — the rest can be withdrawn at any time (rug pull).`,
        ls,
      );
    }
    if (l.creatorLpPercent !== null && l.creatorLpPercent > 5) {
      f.add(
        'creator_lp',
        'Creator holds LP',
        l.creatorLpPercent > 50 ? 75 : 55,
        round1(l.creatorLpPercent),
        5,
        `The creator/owner wallet holds ${fmtPct(l.creatorLpPercent)} of LP tokens and can remove that liquidity.`,
        ls,
      );
    }
  }
  const mcap = m?.marketCapUsd ?? m?.fdvUsd ?? null;
  if (liq !== null && mcap !== null && mcap > 0) {
    const ratio = liq / mcap;
    const pts = ratio < 0.02 ? 40 : ratio < 0.05 ? 20 : 0;
    f.add(
      'thin_liquidity_ratio',
      'Liquidity thin vs market cap',
      pts,
      round3(ratio),
      0.05,
      `Liquidity is ${fmtPct(ratio * 100)} of market cap; a large holder selling would collapse the price.`,
      ls,
    );
  }
  const prevLiq = ctx.previous?.liquidity?.totalLiquidityUsd ?? ctx.previous?.market?.liquidityUsd ?? null;
  const change = pctChange(prevLiq, liq);
  if (change !== null && change <= -25) {
    f.add(
      'liquidity_drop',
      'Liquidity removed',
      change <= -50 ? 90 : 55,
      round1(change),
      -25,
      `Liquidity fell ${fmtPct(-change)} since the previous observation (possible liquidity pull).`,
      ls,
      change <= -50,
    );
  }
  return f.items;
}

// ---------------------------------------------------------------------------
// CONCENTRATION: who holds the supply?
// ---------------------------------------------------------------------------
export function concentrationFactors(s: TokenSnapshot): RiskFactor[] {
  const f = new FactorList('concentration');
  const h = s.holders;
  const hs = h?.sources ?? [];
  if (!h || h.topHolders.length === 0) {
    f.add(
      'holders_unknown',
      'Holder distribution unknown',
      40,
      null,
      null,
      'Top-holder data was unavailable; concentration cannot be ruled out.',
      hs,
    );
    return f.items;
  }
  const circ = circulatingHolders(h.topHolders, s.chain);
  const top = circ[0];
  if (top) {
    const p = top.percent;
    const pts = p >= 50 ? 95 : p >= 20 ? 70 : p >= 10 ? 45 : p >= 5 ? 20 : 0;
    f.add(
      'top_holder',
      'Largest wallet share',
      pts,
      round1(p),
      10,
      `The largest non-pool wallet (${short(top.address)}) holds ${fmtPct(p)} of supply.`,
      hs,
      p >= 50,
    );
  }
  const top10 = circ.slice(0, 10).reduce((a, x) => a + x.percent, 0);
  {
    const pts = top10 >= 80 ? 90 : top10 >= 50 ? 60 : top10 >= 30 ? 35 : top10 >= 20 ? 15 : 0;
    f.add(
      'top10_holders',
      'Top-10 concentration',
      pts,
      round1(top10),
      30,
      `The top 10 non-pool wallets hold ${fmtPct(top10)} of supply.`,
      hs,
      top10 >= 80,
    );
  }
  if (h.holderCount !== null) {
    const pts = h.holderCount < 50 ? 40 : h.holderCount < 200 ? 20 : 0;
    f.add('holder_count', 'Few holders', pts, h.holderCount, 200, `Only ${h.holderCount} holders.`, hs);
  }
  const insiders = circ.filter((x) => x.isInsider === true).reduce((a, x) => a + x.percent, 0);
  if (insiders >= 5) {
    f.add(
      'insiders',
      'Insider wallets',
      insiders >= 20 ? 70 : insiders >= 10 ? 50 : 25,
      round1(insiders),
      5,
      `Wallets flagged as insiders (linked to the creator) hold ${fmtPct(insiders)}.`,
      hs,
    );
  }
  const w = s.wallets;
  if (w) {
    const cluster = w.clusters[0];
    if (cluster && cluster.combinedPercent >= 5) {
      const p = cluster.combinedPercent;
      f.add(
        'wallet_cluster',
        'Coordinated wallet cluster',
        p >= 20 ? 75 : p >= 10 ? 50 : 25,
        round1(p),
        5,
        `${cluster.wallets.length} top holders were funded by the same source (${short(cluster.funder)}) and together hold ${fmtPct(p)} — hidden concentration.`,
        w.sources,
      );
    }
    if (w.newWalletShare !== null && w.analyzedWallets >= 4) {
      const share = w.newWalletShare;
      f.add(
        'fresh_wallets',
        'Newly created holder wallets',
        share >= 0.5 ? 50 : share >= 0.3 ? 30 : 0,
        round3(share),
        0.3,
        `${w.newWallets} of ${w.analyzedWallets} analysed top holders are freshly created wallets (sybil distribution pattern).`,
        w.sources,
      );
    }
  }
  const programHeld = h.topHolders
    .filter((x) => s.chain === 'solana' && x.isContract === true && !x.isLiquidityPool && !x.isBurn)
    .reduce((a, x) => a + x.percent, 0);
  if (programHeld >= 40) {
    f.add(
      'program_held',
      'Supply held by unidentified programs',
      25,
      round1(programHeld),
      40,
      `${fmtPct(programHeld)} of supply sits in program-owned accounts that are not recognised pools or lockers.`,
      hs,
    );
  }
  return f.items;
}

// ---------------------------------------------------------------------------
// DEVELOPER: deployer history and behaviour
// ---------------------------------------------------------------------------
export function developerFactors(s: TokenSnapshot): RiskFactor[] {
  const f = new FactorList('developer');
  const d = s.deployer;
  const ds = d?.sources ?? [];
  if (!d?.address) {
    f.add(
      'deployer_unknown',
      'Deployer unknown',
      15,
      null,
      null,
      'Deployer wallet could not be identified.',
      ds,
    );
  }
  if (d) {
    if (d.honeypotWithSameCreator === true) {
      f.add(
        'deployer_honeypots',
        'Deployer created honeypots',
        95,
        true,
        false,
        'The same deployer previously created honeypot tokens.',
        ds,
        true,
      );
    }
    if (d.knownRugs !== null && d.knownRugs > 0) {
      f.add(
        'deployer_rugs',
        'Deployer rug history',
        90,
        d.knownRugs,
        0,
        'The deployer has a history of rugged tokens.',
        ds,
        true,
      );
    }
    if (d.flaggedMalicious === true) {
      f.add(
        'deployer_malicious',
        'Deployer flagged malicious',
        95,
        true,
        false,
        'The deployer address is flagged as malicious by a security provider.',
        ds,
        true,
      );
    }
    if (d.tokensCreated !== null) {
      const n = d.tokensCreated;
      f.add(
        'serial_deployer',
        'Serial deployer',
        n >= 20 ? 50 : n >= 5 ? 25 : 0,
        n,
        5,
        `The deployer has created ${n} contracts/tokens (serial-launcher pattern).`,
        ds,
      );
    }
    if (d.walletAgeDays !== null) {
      const a = d.walletAgeDays;
      f.add(
        'deployer_fresh',
        'Fresh deployer wallet',
        a < 1 ? 35 : a < 7 ? 15 : 0,
        round1(a),
        7,
        `The deployer wallet is only ${a < 1 ? `${Math.round(a * 24)} hours` : `${a.toFixed(1)} days`} old.`,
        ds,
      );
    }
    if (d.holdsPercent !== null) {
      const p = d.holdsPercent;
      f.add(
        'deployer_holdings',
        'Deployer holds supply',
        p >= 20 ? 70 : p >= 10 ? 45 : p >= 5 ? 25 : 0,
        round1(p),
        5,
        `The deployer still holds ${fmtPct(p)} of supply and can dump it.`,
        ds,
      );
    }
  }
  const a = s.developer;
  if (a) {
    const moved = a.percentOfSupplyMoved ?? 0;
    if (a.sells > 0 || moved > 0) {
      const pts = moved >= 5 ? 80 : moved >= 1 ? 50 : 30;
      f.add(
        'dev_moving_supply',
        a.sells > 0 ? 'Developer selling' : 'Developer transfers',
        pts,
        round1(moved),
        1,
        `In the last ${Math.round(a.lookbackMinutes)} min the developer made ${a.sells} sell(s) and ${a.transfersOut} outgoing transfer(s), moving ${fmtPct(moved)} of supply.`,
        a.sources,
        moved >= 5 && a.sells > 0,
      );
    }
    if (a.transfersToFreshWallets > 0) {
      f.add(
        'dev_fresh_recipients',
        'Dev funds fresh wallets',
        a.transfersToFreshWallets >= 2 ? 60 : 30,
        a.transfersToFreshWallets,
        0,
        `The developer sent tokens to ${a.transfersToFreshWallets} freshly created wallet(s) — supply splitting ahead of a dump.`,
        a.sources,
      );
    }
  }
  return f.items;
}

// ---------------------------------------------------------------------------
// MARKET INTEGRITY: wash trading, abnormal volume, crashes
// ---------------------------------------------------------------------------
export function marketFactors(s: TokenSnapshot): RiskFactor[] {
  const f = new FactorList('market');
  const m = s.market;
  const t = s.trades;
  const ms = srcs(m?.source, t?.source);
  if (t && t.tradeCount >= 20) {
    const rt = t.roundTripVolumeShare;
    f.add(
      'wash_round_trips',
      'Round-trip volume',
      rt >= 0.5 ? 60 : rt >= 0.3 ? 35 : 0,
      round3(rt),
      0.3,
      `${fmtPct(rt * 100)} of recent volume came from wallets that both bought and sold (wash-trading pattern).`,
      ms,
    );
    const top = t.topTraderVolumeShare;
    f.add(
      'dominant_trader',
      'Volume dominated by one wallet',
      top >= 0.4 ? 45 : top >= 0.25 ? 20 : 0,
      round3(top),
      0.25,
      `A single wallet produced ${fmtPct(top * 100)} of recent volume.`,
      ms,
    );
    if (t.tradeSizeCv !== null && t.tradeSizeCv < 0.15) {
      f.add(
        'uniform_sizes',
        'Uniform trade sizes',
        40,
        round3(t.tradeSizeCv),
        0.15,
        `Trade sizes are nearly identical (CV ${t.tradeSizeCv.toFixed(2)}), typical of scripted volume.`,
        ms,
      );
    }
    if (t.repeatedSizeShare >= 0.4) {
      f.add(
        'repeated_sizes',
        'Repeated trade sizes',
        35,
        round3(t.repeatedSizeShare),
        0.4,
        `${fmtPct(t.repeatedSizeShare * 100)} of trades repeat an identical USD size.`,
        ms,
      );
    }
    if (t.tradeCount >= 50) {
      const ratio = t.uniqueTraders / t.tradeCount;
      f.add(
        'few_unique_traders',
        'Few unique traders',
        ratio < 0.15 ? 40 : 0,
        round3(ratio),
        0.15,
        `${t.tradeCount} trades came from only ${t.uniqueTraders} wallets.`,
        ms,
      );
    }
  }
  if (m) {
    const liq = m.liquidityUsd;
    const v24 = m.volumeUsd.h24;
    if (liq && v24 !== null && liq > 0) {
      const r = v24 / liq;
      f.add(
        'volume_liquidity',
        'Abnormal volume vs liquidity',
        r > 50 ? 45 : r > 20 ? 20 : 0,
        round1(r),
        20,
        `24h volume is ${r.toFixed(1)}× pool liquidity (abnormal turnover, often wash trading).`,
        ms,
      );
    }
    const v5 = m.volumeUsd.m5;
    const v1h = m.volumeUsd.h1;
    if (v5 !== null && v1h !== null && v1h > 0 && v5 > 5_000) {
      const accel = (v5 * 12) / v1h;
      f.add(
        'volume_spike',
        'Abnormal volume spike',
        accel > 6 ? 30 : 0,
        round1(accel),
        6,
        `5-minute volume is running at ${accel.toFixed(1)}× the hourly average rate.`,
        ms,
      );
    }
    const c5 = m.priceChangePct.m5;
    const c1 = m.priceChangePct.h1;
    if ((c5 !== null && c5 <= -30) || (c1 !== null && c1 <= -50)) {
      f.add(
        'price_crash',
        'Price crash',
        60,
        round1(Math.min(c5 ?? 0, c1 ?? 0)),
        -30,
        `Price fell sharply (5m ${fmtPct(c5 ?? 0)}, 1h ${fmtPct(c1 ?? 0)}).`,
        ms,
      );
    }
    if (c1 !== null && c1 >= 300) {
      f.add(
        'parabolic',
        'Parabolic pump',
        30,
        round1(c1),
        300,
        `Price rose ${fmtPct(c1, 0)} in one hour — pump-and-dump risk.`,
        ms,
      );
    }
    const tx = m.txns.h1;
    if (tx && tx.buys + tx.sells >= 30 && tx.sells > 2 * tx.buys) {
      f.add(
        'sell_pressure',
        'Heavy sell pressure',
        25,
        tx.sells / Math.max(1, tx.buys),
        2,
        `Sells outnumber buys ${tx.sells}:${tx.buys} over the last hour.`,
        ms,
      );
    }
  }
  return f.items;
}

// ---------------------------------------------------------------------------
// DATA QUALITY: missing data is treated as risk (fail closed)
// ---------------------------------------------------------------------------
export function dataFactors(s: TokenSnapshot, ctx: RiskContext): RiskFactor[] {
  const f = new FactorList('data');
  const failed = s.sources.filter((x) => !x.ok).map((x) => x.name);
  if (!s.market)
    f.add(
      'no_market',
      'No market data',
      50,
      false,
      true,
      'No market data source returned data for this token.',
      [],
    );
  if (s.market) {
    const age = (ctx.now.getTime() - Date.parse(s.market.fetchedAt)) / 1000;
    if (age > 300)
      f.add(
        'stale_market',
        'Stale market data',
        20,
        Math.round(age),
        300,
        `Market data is ${Math.round(age)}s old.`,
        [s.market.source],
      );
  }
  if (failed.length > 0) {
    f.add(
      'source_failures',
      'Data source failures',
      Math.min(30, failed.length * 8),
      failed.length,
      0,
      `Sources failed: ${failed.slice(0, 6).join(', ')}.`,
      failed,
    );
  }
  // Provider red flags not already covered by a dedicated factor (avoids double counting).
  const uncovered = s.warnings.filter(
    (w) =>
      w.level === 'danger' &&
      !HANDLED_WARNING_CODES.has(w.code) &&
      !COVERED_TOPICS.test(`${w.code} ${w.message}`),
  );
  for (const w of uncovered.slice(0, 3)) {
    f.add(
      `provider_${w.source}_${w.code}`.slice(0, 80),
      `Provider warning: ${w.code}`,
      25,
      w.code,
      null,
      w.message,
      [w.source],
    );
  }
  return f.items;
}

const HANDLED_WARNING_CODES = new Set([
  'no_code',
  'mint_not_found',
  'not_a_mint',
  'unknown_token_program',
  'fake_token',
  'airdrop_scam',
]);
/** Topics with dedicated factors; provider warnings about them are not scored twice. */
const COVERED_TOPICS =
  /freeze|mint|liquidity|\blp\b|holder|owner|concentrat|tax|fee|mutable|metadata|creator|insider|supply|rug|honeypot|proxy|upgrad/i;

function maxOf(...vals: (number | null | undefined)[]): number | null {
  const xs = vals.filter((v): v is number => typeof v === 'number' && Number.isFinite(v));
  return xs.length > 0 ? Math.max(...xs) : null;
}
const round1 = (v: number) => Math.round(v * 10) / 10;
const round3 = (v: number) => Math.round(v * 1000) / 1000;
