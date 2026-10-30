#!/usr/bin/env python3
"""X4Y4 agreement with the normative reference (vendored reference/model.py,
SHA-256 pinned) on the official seeded synthetic weights. Requires numpy.
Exactness of the RTL is separate (golden_decoder.py)."""
import math, os, tempfile, unittest, filecmp
import numpy as np
import kda_model as km, mla_model as mm, nano_ref

def cos(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return float(a @ b / np.linalg.norm(a) / np.linalg.norm(b))

class ReferenceTests(unittest.TestCase):
    def test_vendored_reference_unmodified(self):
        nano_ref.check_vendored()

    def test_committed_weight_roms_are_official_generator_output(self):
        with tempfile.TemporaryDirectory() as d:
            mm.gen_hex(d, 128)
            for f in ("q.hex", "s.hex", "z.hex", "knorm.hex"):
                self.assertTrue(filecmp.cmp(os.path.join(d, f), os.path.join(mm.HERE, "mla_weights", f), shallow=False), f)

    def _mla_vs_ref(self, seq, W, group):
        rows = nano_ref.ref_mla_trace(seq, group)
        st, worst = None, 1.0
        for (t, ss), r in zip(seq, rows):
            if ss or st is None: st = mm.new_state()
            g = mm.int_step(W, st, t)
            self.assertEqual(g["T"], r["T"])
            c = cos(np.array(g["out"]) / 65536, r["out"]); worst = min(worst, c)
            self.assertGreater(c, 0.999, (t, g["T"]))
            self.assertGreater(cos(np.array(g["lat"]) / 65536, r["lat"]), 0.99999)
            self.assertLess(np.max(np.abs(np.array(g["p"]) / 65536 - r["p"])), 0.02)
        return worst

    def test_mla_fixed_point_tracks_reference_full_cache(self):
        a, b = nano_ref.public_tokens()
        seq = [(t, int(i == 0)) for i, t in enumerate(a + b)] + [(b[0], 1), (b[1], 0)]
        self.assertEqual(len(a + b), mm.MAX_SEQ)
        print(f"\n  MLA vs model.py, 66 tokens (64-entry cache + restart), worst out cos "
              f"{self._mla_vs_ref(seq, mm.Weights(), 128):.6f}")

    def test_mla_group64_tracks_reference(self):
        with tempfile.TemporaryDirectory() as d:
            mm.gen_hex(d, 64)
            W = mm.Weights(d, 64)
            seq = [(5, 1), (300, 0), (17, 0), (511, 1), (2, 0)]
            print(f"\n  MLA group 64 vs model.py, worst out cos {self._mla_vs_ref(seq, W, 64):.6f}")

    def test_kda_structure_matches_reference(self):
        # float64 KDA model (rank-32 f/z, RMS eps 1e-5) == reference _kda in float32
        ref = nano_ref.ref_model(); fs = km.float_new_state()
        for t in (0, 1, 511, 7, 300, 42):
            x = np.array([(km.x_u(t, i) - 128) / 32 for i in range(64)], np.float32)
            r = ref._kda(0, x)
            fo = np.array(km.float_step(fs, t)["y"], np.float32) @ ref.w["L0.kda.o"]
            self.assertLess(np.max(np.abs(r - fo)) / np.max(np.abs(r)), 1e-5, t)

    def test_kda_fixed_point_vs_reference(self):
        # Measured floor of the X4Y3 KDA fixed point (not a design target): the
        # first token's tiny q.S makes Q16 resolution coarse (see CORRECTNESS.md).
        ref = nano_ref.ref_model(); st = km.new_state(); cs = []
        for t in (0, 1, 511, 7, 300, 42, 9, 128):
            x = np.array([(km.x_u(t, i) - 128) / 32 for i in range(64)], np.float32)
            cs.append(cos(np.array(km.int_step(st, t)["out"]) / 65536, ref._kda(0, x)))
        print("\n  KDA int vs model.py out cos: " + " ".join(f"{c:.4f}" for c in cs))
        self.assertGreater(min(cs), 0.98)

if __name__ == "__main__":
    unittest.main()
