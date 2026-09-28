"""Educational rug-pull SIMULATION for explainer videos and demos.

This is a self-contained teaching model. It has NO blockchain connection, NO
wallet, NO transaction signing, and NO DEX calls. Everything below is plain
arithmetic on in-memory numbers, so it cannot move, drain, or touch any real
liquidity. Its only purpose is to show, step by step, how a liquidity rug pull
plays out so viewers can recognise one.

The pool uses the standard constant-product AMM formula (x * y = k), the same
public math Uniswap/Raydium document, so the price moves realistically as
simulated buyers trade.

Run it:
    python -m rugguard.simulation
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field


@dataclass
class Pool:
    """A constant-product (x*y=k) liquidity pool, simulated in memory only."""

    sol: float  # quote reserve
    tokens: float  # base reserve

    @property
    def k(self) -> float:
        return self.sol * self.tokens

    @property
    def price(self) -> float:
        """SOL per token."""
        return self.sol / self.tokens if self.tokens else 0.0

    def buy(self, sol_in: float) -> float:
        """Simulate buying tokens with `sol_in` SOL. Returns tokens received."""
        new_sol = self.sol + sol_in
        new_tokens = self.k / new_sol
        tokens_out = self.tokens - new_tokens
        self.sol, self.tokens = new_sol, new_tokens
        return tokens_out


@dataclass
class Buyer:
    name: str
    sol_spent: float = 0.0
    tokens: float = 0.0

    def value(self, price: float) -> float:
        return self.tokens * price


@dataclass
class Simulation:
    pool: Pool
    dev_lp_sol: float  # SOL the dev put into the pool as liquidity
    buyers: list[Buyer] = field(default_factory=list)
    log: list[str] = field(default_factory=list)

    def say(self, line: str) -> None:
        self.log.append(line)

    def buy(self, name: str, sol_in: float) -> None:
        buyer = Buyer(name)
        buyer.tokens = self.pool.buy(sol_in)
        buyer.sol_spent = sol_in
        self.buyers.append(buyer)
        self.say(
            f"  {name} buys with {sol_in:>5.1f} SOL -> {buyer.tokens:>12,.0f} tokens "
            f"| price now {self.pool.price:.8f} SOL"
        )

    def rug(self) -> float:
        """The dev pulls the liquidity: withdraw the SOL, price collapses.

        Returns the SOL the dev walks away with. In a real rug this is the SOL
        that BUYERS paid in, which is why it is theft, not a withdrawal of the
        dev's own money.
        """
        drained = self.pool.sol
        self.pool.sol = 0.0  # pool emptied of quote reserve
        dev_profit = drained - self.dev_lp_sol
        self.say("")
        self.say("  *** DEV PULLS LIQUIDITY ***")
        self.say(
            f"  Dev removes {drained:.1f} SOL from the pool "
            f"(they seeded only {self.dev_lp_sol:.1f}, so {dev_profit:.1f} of it is buyers' money)."
        )
        self.say(f"  Token price collapses to {self.pool.price:.8f} SOL. Buyers cannot sell for anything.")
        return drained


def run(scenario: str = "classic") -> Simulation:
    """Run the demo scenario and return the finished simulation."""
    dev_lp = 10.0
    # Dev seeds the pool: 10 SOL against 1,000,000,000 tokens.
    sim = Simulation(pool=Pool(sol=dev_lp, tokens=1_000_000_000), dev_lp_sol=dev_lp)

    sim.say("=" * 70)
    sim.say("RUG PULL SIMULATION  (teaching model, no real blockchain)")
    sim.say("=" * 70)
    sim.say(f"Dev launches token and seeds pool: {sim.pool.sol:.1f} SOL / "
            f"{sim.pool.tokens:,.0f} tokens")
    sim.say(f"Starting price: {sim.pool.price:.8f} SOL per token")
    sim.say("")
    sim.say("Buyers arrive (each buy pushes the price up):")

    for name, amount in [("Buyer A", 2.0), ("Buyer B", 5.0), ("Buyer C", 3.0),
                          ("Buyer D", 8.0), ("Buyer E", 4.0)]:
        sim.buy(name, amount)

    total_in = sum(b.sol_spent for b in sim.buyers)
    peak_price = sim.pool.price
    sim.say("")
    sim.say(f"Buyers have paid in {total_in:.1f} SOL total. "
            f"On paper their tokens are 'worth' the pumped price.")

    sim.rug()

    sim.say("")
    sim.say("Aftermath — what each buyer is left with:")
    sim.say(f"  {'Buyer':<9} {'paid (SOL)':>11} {'value at peak':>14} {'value after rug':>16}")
    lost = 0.0
    for b in sim.buyers:
        lost += b.sol_spent
        sim.say(f"  {b.name:<9} {b.sol_spent:>11.1f} {b.value(peak_price):>14.1f} "
                f"{b.value(sim.pool.price):>16.4f}")
    sim.say("")
    sim.say(f"Buyers lost ~{lost:.1f} SOL. The dev walked away with it.")
    sim.say("")
    sim.say("How buyers could have spotted it BEFORE buying:")
    sim.say("  - LP was not locked or burned, so the dev could withdraw it at any time.")
    sim.say("  - That single check is what `python -m rugguard scan <mint>` reports.")
    sim.say("=" * 70)
    return sim


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Educational rug-pull simulation (no blockchain, nothing real is moved).",
    )
    parser.add_argument("--scenario", default="classic", help="scenario name (currently: classic)")
    args = parser.parse_args(argv)
    sim = run(args.scenario)
    print("\n".join(sim.log))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
