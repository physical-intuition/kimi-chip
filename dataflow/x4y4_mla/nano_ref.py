#!/usr/bin/env python3
"""Access to the vendored, unmodified nano-kpu reference (third_party/nano-kpu,
pinned commit, SHA-256 checked). Builds a real reference.model.RefModel so the
float arbiter for every operator here is model.py itself, not a re-derivation.

Weights: the official seeded synthetic generator (reference/gen_weights.py)
for everything, with L0's KDA tensors replaced by the X4Y3 placeholder
parameters re-encoded in the reference int4/int16 formats (the KDA RTL still
uses those placeholders). Requires numpy.
"""
import dataclasses, hashlib, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "third_party", "nano-kpu"))
SHA256 = {
    "__init__.py": "61da8956a79b6adea9f406af5d05d802d97bdb3e038ccdfc0c91be8f9e47f5ea",
    "config.py": "c5880699f201380e0acf720be06c39c90aa3efbda13ca4ea4f056763fd2e2744",
    "gen_weights.py": "ffff8f47692f500aed51ec79a16514f5d31c60e2db0190aadf311f9263b0d5f9",
    "model.py": "a002f6bee18c449829e6b803cc8b9251aa9025b5e31674b9a8b7c819021534a5",
    "prng.py": "1dc4f7950d1393032ae3f1eafc5989b249021de00509c121dcb14cb1d073a661",
}
PUBLIC_SEED = 20260706                 # harness/seeds_public.json

def check_vendored():
    for f, want in SHA256.items():
        with open(os.path.join(ROOT, "reference", f), "rb") as fh:
            got = hashlib.sha256(fh.read()).hexdigest()
        if got != want:
            raise RuntimeError(f"vendored reference/{f} modified: {got}")

def _import():
    check_vendored()
    if ROOT not in sys.path: sys.path.insert(0, ROOT)
    import numpy as np
    from reference import config, model, gen_weights
    return np, config, model, gen_weights

def nano_config(group=128):
    _, config, _, _ = _import()
    return dataclasses.replace(config.CONFIGS["nano"], group_size=group)

def official_weights(group=128, seed=PUBLIC_SEED):
    _, _, _, gw = _import()
    return gw.gen_weights(nano_config(group), seed)

def _pack(np, codes):                  # codes uint [k, n] -> reference packed [k/2, n]
    return (codes[0::2] | (codes[1::2] << 4)).astype(np.int64)

def kda_placeholder_weights(W, group=128):
    """Replace L0.kda.* with the X4Y3 placeholders in reference encodings:
    w = (code - 8) * 64 * 2^-12 = (code - 8) / 64 (z = 8, s = 64), conv taps
    Q16 -> Q4.11 (reference window is oldest-first, so lag j is column 3-j),
    dt_bias Q16 -> Q4.11, onorm 1 + w (Q2.13 offset), A unsigned Q8.8."""
    import kda_model as km
    np, _, model, _ = _import()
    cfg = nano_config(group)
    W = dict(W)
    for m, nm in enumerate(["q", "k", "v", "b", "f1", "f2", "g1", "g2", "o"]):
        k, n = model.matmul_shapes(cfg)[f"L0.kda.{nm}"]
        assert (k, n) == (km.NIN[m], km.NOUT[m]), (nm, k, n)
        codes = np.array([[km.w_u(m, o, i) for o in range(n)] for i in range(k)], np.int64)
        ng = -(-k // min(group, k))
        W[f"L0.kda.{nm}.q"] = _pack(np, codes)
        W[f"L0.kda.{nm}.s"] = np.full((ng, n), 64, np.int64)
        W[f"L0.kda.{nm}.z"] = np.full((ng, n), 8, np.int64)
    for s, nm in enumerate(["qconv", "kconv", "vconv"]):
        W[f"L0.kda.{nm}"] = np.array([[km.conv_w(s * 64 + c, 3 - j) >> 5 for j in range(4)]
                                      for c in range(64)], np.int64)
    W["L0.kda.A"] = np.array(km.A_Q88, np.int64)
    W["L0.kda.dtb"] = np.array([km.dt_bias(c) >> 5 for c in range(64)], np.int64)
    W["L0.kda.onorm.w"] = np.array([(km.onorm(j) - 65536) >> 3 for j in range(32)], np.int64)
    return W

def ref_model(group=128, seed=PUBLIC_SEED):
    """reference.model.RefModel on official weights + X4Y3 KDA placeholders."""
    _, _, model, _ = _import()
    cfg = nano_config(group)
    return model.RefModel(cfg, kda_placeholder_weights(official_weights(group, seed), group))

def ref_mla_trace(seq, group=128, h_codes=None):
    """Run reference RefModel._mla (layer 1) on the staged placeholder input
    h = (h_u - 128) / 64 for (token, seq_start) pairs. Returns per-token dicts
    with out, ctx (the reference dump), and lat / softmax p recomputed with the
    reference's own rmsnorm/softmax on its cached K."""
    import mla_model as mm
    np, _, model, _ = _import()
    ref = ref_model(group)
    c, w, rows = ref.cfg, ref.w, []
    for t, ss in seq:
        if ss or not rows: ref.reset()
        hu = h_codes(t) if h_codes else [mm.h_u(t, i) for i in range(c.d_model)]
        h = np.array([(x - 128) / 64 for x in hu], np.float32)
        ref.dump = {}
        out = ref._mla(1, h)
        ctx = ref.dump[f"p{ref.pos}.L1.mla.ctx"].reshape(-1)
        lat = model.rmsnorm(h @ w["L1.mla.wc"], w["L1.mla.knorm.w"])
        q = np.concatenate([(h @ w["L1.mla.wq_c"]).reshape(c.n_heads, c.mla_dk),
                            (h @ w["L1.mla.wq_r"]).reshape(c.n_heads, c.mla_dr)], axis=-1)
        K = np.stack(ref.kv_k[1])
        scale = np.float32(1.0 / np.sqrt(c.mla_dk + c.mla_dr))
        p = np.concatenate([model.softmax((K[:, hd, :] @ q[hd]) * scale) for hd in range(c.n_heads)])
        rows.append(dict(out=out, ctx=ctx, lat=lat, p=p, T=len(ref.kv_k[1])))
        ref.pos += 1
    return rows

def public_tokens(seed=PUBLIC_SEED):
    """The two public teacher-forced prompts (lengths seq_lens = 48, 16)."""
    _, _, _, gw = _import()
    cfg = nano_config()
    return [[int(t) for t in gw.gen_tokens(cfg, seed, i)] for i in range(len(cfg.seq_lens))]
