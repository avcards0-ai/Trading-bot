import unittest

from rugguard.simulation import Pool, run


class PoolMathTests(unittest.TestCase):
    def test_constant_product_holds_through_a_buy(self):
        pool = Pool(sol=10, tokens=1_000_000_000)
        k_before = pool.k
        pool.buy(5)
        self.assertAlmostEqual(pool.k, k_before, delta=k_before * 1e-9)

    def test_buying_raises_price(self):
        pool = Pool(sol=10, tokens=1_000_000_000)
        start = pool.price
        pool.buy(5)
        self.assertGreater(pool.price, start)


class ScenarioTests(unittest.TestCase):
    def test_rug_empties_the_pool_and_crashes_price(self):
        sim = run()
        self.assertEqual(sim.pool.sol, 0.0)
        self.assertEqual(sim.pool.price, 0.0)
        # Every buyer's post-rug holdings are worth nothing.
        self.assertTrue(all(b.value(sim.pool.price) == 0.0 for b in sim.buyers))

    def test_it_is_only_a_simulation(self):
        """No network/wallet imports: this model cannot touch anything real."""
        import rugguard.simulation as s

        source = open(s.__file__, encoding="utf-8").read()
        for forbidden in ("import requests", "urllib", "solana", "web3", "private_key", "signTransaction"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
