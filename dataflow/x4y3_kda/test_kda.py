#!/usr/bin/env python3
"""X4Y3 KDA-specific tests of the bit-exact model (RTL equality: golden_kda.py)."""
import math, random, unittest
import kda_model as m

class KdaTests(unittest.TestCase):
    def test_unsigned_mac_decomposition_is_signed_dot(self):
        rnd = random.Random(1)
        for n in (8, 64):
            for _ in range(200):
                xu = [rnd.randrange(256) for _ in range(n)]; wu = [rnd.randrange(16) for _ in range(n)]
                hi = sum((x >> 4) * w for x, w in zip(xu, wu)); lo = sum((x & 15) * w for x, w in zip(xu, wu))
                raw = 16 * hi + lo - 8 * sum(xu) - 128 * sum(wu) + 1024 * n
                self.assertEqual(raw, sum((x - 128) * (w - 8) for x, w in zip(xu, wu)))
                self.assertLess(16 * hi + lo, 1 << 24)   # fits 24-bit accumulator delta

    def test_projection_dimensions(self):
        st = m.new_state(); r = m.int_step(st, 5)
        for key, n in dict(q=64, k=64, v=64, f=64, z=64, alpha=64, beta=2, attn=64, y=64, out=64).items():
            self.assertEqual(len(r[key]), n, key)
        self.assertEqual(sum(len(t) for t in r["hist"]), 576)
        self.assertEqual(sum(len(row) for Sh in r["S"] for row in Sh), 2048)

    def test_conv_history_shifts_across_tokens(self):
        st = m.new_state(); pres = []
        for t in (3, 9, 200, 77, 1):
            pres.append(m.int_step(st, t)["pre"])
            for tap in range(3):
                want = pres[-1 - tap] if len(pres) > tap else [0] * 192
                self.assertEqual(st["hist"][tap], want)

    def test_conv_uses_history(self):
        a = m.int_step(m.new_state(), 9)
        st = m.new_state(); m.int_step(st, 3); b = m.int_step(st, 9)
        self.assertEqual(a["pre"], b["pre"]); self.assertNotEqual(a["q"], b["q"])

    def test_l2_norm_unit_heads(self):
        r = m.int_step(m.new_state(), 21)
        for vec in (r["q"], r["k"]):
            for h in range(2):
                n = sum((x / 65536) ** 2 for x in vec[h * 32:(h + 1) * 32])
                self.assertAlmostEqual(n, 1.0, delta=2e-3)

    def test_gate_ranges(self):
        for t in range(0, 512, 37):
            r = m.int_step(m.new_state(), t)
            self.assertTrue(all(0 < b < 65536 for b in r["beta"]))
            self.assertTrue(all(65536 * math.exp(-5) - 2 <= a <= 65536 for a in r["alpha"]))

    def test_luts_track_float(self):
        for x in range(-10 * 65536, 10 * 65536, 997):
            self.assertAlmostEqual(m.sigmoid_q(x) / 65536, 1 / (1 + math.exp(-x / 65536)), delta=1e-3)
        for s in range(0, 65537, 101):
            self.assertAlmostEqual(m.exp5_q(s) / 65536, math.exp(-5 * s / 65536), delta=1e-3)

    def test_delta_rule_writes_value(self):
        # beta=1, unit k, S=0: one update stores v along k, so k.S == v; a
        # second identical update has ~zero prediction error (S unchanged).
        rnd = random.Random(2)
        raw = [rnd.uniform(-1, 1) for _ in range(32)]; nrm = math.sqrt(sum(x * x for x in raw))
        k = [round(x / nrm * 65536) for x in raw]; v = [round(rnd.uniform(-0.5, 0.5) * 65536) for _ in range(32)]
        S = [[0] * 32 for _ in range(32)]
        m.delta_update(S, k, v, 65536)
        for j in range(32):
            self.assertAlmostEqual(sum(k[i] * S[i][j] for i in range(32)) / 2**32, v[j] / 65536, delta=1e-3)
        before = [row[:] for row in S]; m.delta_update(S, k, v, 65536)
        self.assertLess(max(abs(a - b) for ra, rb in zip(S, before) for a, b in zip(ra, rb)), 64)

    def test_fixed_point_tracks_float_reference(self):
        st, fs = m.new_state(), m.float_new_state()
        for t in (0, 1, 511, 7):
            g, f = m.int_step(st, t), m.float_step(fs, t)
            Sg = [x / 65536 for Sh in g["S"] for row in Sh for x in row]
            Sf = [x for Sh in f["S"] for row in Sh for x in row]
            self.assertLess(max(abs(a - b) for a, b in zip(Sg, Sf)), 1e-3)
            self.assertLess(max(abs(a / 65536 - b) for a, b in zip(g["attn"], f["attn"])), 1e-4)

if __name__ == "__main__":
    unittest.main()
