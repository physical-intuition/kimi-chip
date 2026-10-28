#!/usr/bin/env python3
"""X4Y4 MLA tests of the bit-exact model (RTL equality: golden_decoder.py; float
reference agreement: test_reference.py). Pure Python, no numpy."""
import math, random, unittest
from fractions import Fraction
import mla_model as m

W = m.Weights()

class MlaModelTests(unittest.TestCase):
    def test_geometry(self):
        self.assertEqual(m.WORDS, 72)                    # 144 values = dc 128 + dr 16 (docs)
        self.assertEqual(m.layout(128)[2:], (17920, 432))
        self.assertEqual(m.layout(64)[2:], (17920, 560))  # wk_c / wv get 2 groups
        self.assertEqual(m.INV_SQRT_QK, round(65536 / math.sqrt(48)))

    def test_zero_point_mac_decomposition(self):
        # The RTL engine identity: sum (x-128)(q-z) from unsigned nibble MACs.
        rnd = random.Random(1)
        for g in (64, 128):
            for _ in range(200):
                xu = [rnd.randrange(256) for _ in range(g)]; q = [rnd.randrange(16) for _ in range(g)]
                z = rnd.randrange(16)
                hi = sum((x >> 4) * w for x, w in zip(xu, q)); lo = sum((x & 15) * w for x, w in zip(xu, q))
                raw = 16 * hi + lo - z * sum(xu) - 128 * sum(q) + 128 * z * g
                self.assertEqual(raw, sum((x - 128) * (w - z) for x, w in zip(xu, q)))
                self.assertLess(max(hi, lo), 1 << 24)

    def test_projection_is_floor_of_exact_dequant(self):
        # value = floor(2^16 * sum_i x_i * (q - z) * s * 2^-12), x = (c-128) 2^(e-16)
        rnd = random.Random(2)
        for n in ("wc", "wk_c", "o"):
            k, nout = m.SHAPE[n]
            for e in (0, 5, 10, 16):
                codes = [rnd.randrange(256) for _ in range(k)]
                got = m.proj(W, n, codes, e)
                for o in rnd.sample(range(nout), 4):
                    g = min(W.group, k)
                    exact = sum(Fraction((codes[i] - 128) * (W.q(n, i, o) - W.z(n, i // g, o)) * W.s(n, i // g, o))
                                * Fraction(2) ** (e - 16 - 12 + 16) for i in range(k))
                    self.assertEqual(got[o], max(-2**31, min(2**31 - 1, math.floor(exact))))

    def test_quantizer(self):
        rnd = random.Random(3)
        for _ in range(300):
            vals = [rnd.randrange(-2**rnd.randrange(1, 31), 2**rnd.randrange(1, 31)) for _ in range(64)]
            e = m.choose_e(vals); codes = m.quant(vals, e)
            mx = max(abs(v) for v in vals)
            self.assertTrue(mx >> e < 128 or e == 16)
            self.assertTrue(e == 0 or mx >> (e - 1) >= 128)          # smallest such e
            for v, c in zip(vals, codes):
                self.assertTrue(0 <= c <= 255)
                if abs(v) < 127 << e:
                    self.assertLessEqual(abs((c - 128) * 2**e - v), 2**e // 2 if e else 0)

    def test_exp_lut(self):
        for d in range(0, 16 * 65536, 4099):
            self.assertAlmostEqual(m.exp_neg_q(d) / 65536, math.exp(-d / 65536), delta=1.5e-4)
        self.assertEqual(m.exp_neg_q(0), 65536)
        self.assertEqual(m.exp_neg_q(16 * 65536), 0)

    def test_dimensions_and_latent_norm(self):
        g = m.int_step(W, m.new_state(), 5)
        for key, n in dict(hu=64, latr=128, lat=128, latu=128, qc=64, qr=32, kr=16, kc=64, v=64,
                           score=2, p=2, ctx=64, ctxu=64, out=64).items():
            self.assertEqual(len(g[key]), n, key)
        # lat / (1 + w) has unit RMS
        rms = math.sqrt(sum((x / 65536 / (1 + W.knorm[i] / 8192)) ** 2 for i, x in enumerate(g["lat"])) / 128)
        self.assertAlmostEqual(rms, 1.0, delta=2e-3)

    def test_first_token_attends_only_to_itself(self):
        g = m.int_step(W, m.new_state(), 77)
        self.assertEqual(g["p"], [65536, 65536])
        self.assertEqual(g["ctx"], g["v"])                        # p = 1 -> ctx = v exactly

    def test_softmax_over_cache_and_causality(self):
        st = m.new_state(); outs = []
        toks = [3, 9, 200, 77, 1, 450, 31]
        for n, t in enumerate(toks):
            g = m.int_step(W, st, t); outs.append(g["out"])
            self.assertEqual(g["T"], n + 1)
            self.assertEqual(len(g["score"]), 2 * (n + 1))
            for hd in range(2):
                ph = g["p"][hd * g["T"]:(hd + 1) * g["T"]]
                self.assertTrue(0 <= 65536 - sum(ph) < g["T"])     # floor division loses < 1 LSB each
                sc = g["score"][hd * g["T"]:(hd + 1) * g["T"]]
                self.assertEqual(ph.index(max(ph)), sc.index(max(sc)))
        # a different later token never changes an earlier position (causal);
        # changing an earlier token does change later outputs (cache is used)
        st2 = m.new_state()
        for n, t in enumerate(toks[:4] + [99]):
            g2 = m.int_step(W, st2, t)
            if n < 4: self.assertEqual(g2["out"], outs[n])
        st3 = m.new_state()
        for t in [4] + toks[1:4]: g3 = m.int_step(W, st3, t)
        self.assertNotEqual(g3["out"], outs[3])

    def test_shared_rope_free_key_part(self):
        st = m.new_state()
        for t in (8, 13): g = m.int_step(W, st, t)
        for hd in range(2):
            q = g["qc"][hd * 32:(hd + 1) * 32] + g["qr"][hd * 16:(hd + 1) * 16]
            for ti, row in enumerate(st["cache"]):
                k = row[hd * 32:(hd + 1) * 32] + row[64:80]           # kr shared by both heads
                want = m.mulq(m.sat32(sum(a * b for a, b in zip(q, k)) >> 16), m.INV_SQRT_QK)
                self.assertEqual(g["score"][hd * 2 + ti], want)

    def test_cache_capacity_and_restart(self):
        st = m.new_state()
        for t in range(64): m.int_step(W, st, t)
        with self.assertRaises(OverflowError): m.int_step(W, st, 64)
        self.assertEqual(len(st["cache"]), 64)
        self.assertEqual(m.int_step(W, m.new_state(), 9), m.int_step(W, m.new_state(), 9))

    def test_cache_word_packing(self):
        st = m.new_state(); g = m.int_step(W, st, 21)
        words = m.cache_words(st)
        vals = g["kc"] + g["kr"] + g["v"]
        for w, x in enumerate(words):
            lo, hi = x & 0xffffffff, x >> 32
            self.assertEqual((lo ^ 2**31) - 2**31, vals[2 * w]); self.assertEqual((hi ^ 2**31) - 2**31, vals[2 * w + 1])

if __name__ == "__main__":
    unittest.main()
