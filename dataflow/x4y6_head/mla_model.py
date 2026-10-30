#!/usr/bin/env python3
"""Bit-exact integer model of the X4Y4 MLA datapath (layer 1, NoPE MLA).

Normative math (reference/model.py RefModel._mla), per token with input h:
  lat = rmsnorm(h @ wc, knorm)            dc = 128, eps 1e-5, gain 1 + w
  qc = h @ wq_c  [H, dk]   qr = h @ wq_r  [H, dr]   kr = h @ wk_r  [dr] shared
  kc = lat @ wk_c [H, dk]  v  = lat @ wv  [H, dv]
  per head: p = softmax([qc, qr] . [kc_t, kr_t] / sqrt(dk + dr)) over all
  cached t (including this token); ctx = p @ V; out = concat(ctx) @ o

Chip number formats (free per docs/quantization.md; chosen here):
  * values are signed Q16.16 int32, saturating; products floor(a*b / 2^16)
  * matmul inputs are INT8 codes c with value (c - 128) * 2^(e - 16); h has
    the fixed e = 10 (2^-6 steps), lat and ctx pick e per vector (smallest
    e in [0, 16] with max|x| >> e < 128), code = sat8(round_half_up(x / 2^e))
  * weights are the reference int4 format: w = (q - z) * s * 2^-12 with
    per-(group, column) zero z and Q3.12 scale s, group = min(G, fan_in);
    a projection output is floor(sum_g s_g * sum_i (c_i - 128)(q_i - z_g) * 2^(e-12))
  * softmax: max subtraction, exp(-d) from a 513-entry LUT over [0, 16] with
    linear interpolation (step 1/32), p_t = floor(e_t * 2^16 / sum e)
  * the KV cache holds kc (64), kr (16), v (64) per position as Q16.16
    words: 72 x 64-bit SRAM words, value 2w in bits [31:0], 2w+1 in [63:32]

The MLA input h is STAGED: in the reference it is rmsnorm(res_mix(...)) of
the layer-0 (KDA + MoE) output, which needs X4Y5 operators. Here h is a
deterministic placeholder code vector h_u(token).

Weights come from mla_weights/*.hex, written by gen_hex() from the official
reference/gen_weights.py (numpy); everything else in this file is pure Python.
"""
import math, os, sys

H, DK, DR, DV, DC, D = 2, 32, 16, 32, 128, 64
QK = DK + DR
MAX_SEQ = 64
WORDS = (H * DK + DR + H * DV) // 2          # 72 cache words per position
H_E = 10                                       # h code scale 2^-6
RMS_EPS_Q32 = round(1e-5 * 2**32)
INV_SQRT_QK = round(65536 / math.sqrt(QK))
EXPN = [round(65536 * math.exp(-i / 32)) for i in range(513)]
# engine order: matrix m = 9 + index (m = 0..8 are the KDA matrices)
MATS = [("wc", D, DC), ("wq_c", D, H * DK), ("wq_r", D, H * DR), ("wk_r", D, DR),
        ("wk_c", DC, H * DK), ("wv", DC, H * DV), ("o", H * DV, D)]
SHAPE = {n: (k, o) for n, k, o in MATS}
HERE = os.path.dirname(os.path.abspath(__file__))

def sat32(x): return max(-2**31, min(2**31 - 1, x))
def sat8(x): return max(-128, min(127, x))
def mulq(a, b): return sat32((a * b) >> 16)
def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q

def h_u(t, i):                                 # STAGED placeholder MLA input code
    return (t * 89 + i * 113 + ((t ^ (i * 3)) & 63) * 3 + 17) & 255

def exp_neg_q(d):                              # exp(-d), d >= 0 in Q16
    i, fr = d >> 11, d & 2047
    if i >= 512: return 0
    return EXPN[i] - (((EXPN[i] - EXPN[i + 1]) * fr) >> 11)

def choose_e(vals):
    m, e = max(abs(v) for v in vals), 0
    while e < 16 and (m >> e) >= 128: e += 1
    return e

def quant(vals, e):
    half = (1 << (e - 1)) if e else 0
    return [sat8((v + half) >> e) + 128 for v in vals]

def layout(group):
    """Byte/scale base offsets of each matrix in the flat ROM images."""
    qb, sb, qo, so = {}, {}, 0, 0
    for n, k, o in MATS:
        g = min(group, k); assert k % g == 0
        qb[n], sb[n] = qo, so
        qo += k // 2 * o; so += k // g * o
    return qb, sb, qo, so

def read_hex(path, bits):
    with open(path) as f: vals = [int(l, 16) for l in f if l.strip()]
    return [v - (1 << bits) if v >> (bits - 1) else v for v in vals] if bits == 16 else vals

class Weights:
    def __init__(self, wdir=os.path.join(HERE, "mla_weights"), group=128):
        self.group = group
        self.qb, self.sb, nq, ns = layout(group)
        self.qrom = read_hex(os.path.join(wdir, "q.hex"), 8)
        self.srom = read_hex(os.path.join(wdir, "s.hex"), 16)
        self.zrom = read_hex(os.path.join(wdir, "z.hex"), 8)
        self.knorm = read_hex(os.path.join(wdir, "knorm.hex"), 16)
        assert (len(self.qrom), len(self.srom), len(self.zrom), len(self.knorm)) == (nq, ns, ns, DC)
    def q(self, n, i, o):
        b = self.qrom[self.qb[n] + (i >> 1) * SHAPE[n][1] + o]
        return (b >> 4) if i & 1 else (b & 15)
    def s(self, n, g, o): return self.srom[self.sb[n] + g * SHAPE[n][1] + o]
    def z(self, n, g, o): return self.zrom[self.sb[n] + g * SHAPE[n][1] + o]

def proj(W, n, codes, e):
    k, nout = SHAPE[n]; g = min(W.group, k); assert len(codes) == k
    out = []
    for o in range(nout):
        acc = 0
        for gi in range(k // g):
            z = W.z(n, gi, o)
            raw = sum((codes[i] - 128) * (W.q(n, i, o) - z) for i in range(gi * g, (gi + 1) * g))
            acc += raw * W.s(n, gi, o)
        out.append(sat32(acc >> (12 - e) if e <= 12 else acc << (e - 12)))
    return out

def new_state(): return dict(cache=[])

def int_step(W, st, t, hu=None, he=H_E):
    """X4Y5: hu / he = INT8 input codes and exponent (default: X4Y4 placeholder, e = 10)."""
    hu = [h_u(t, i) for i in range(D)] if hu is None else hu
    latr = proj(W, "wc", hu, he)
    qc, qr, kr = proj(W, "wq_c", hu, he), proj(W, "wq_r", hu, he), proj(W, "wk_r", hu, he)
    r = math.isqrt((sum(x * x for x in latr) >> 7) + RMS_EPS_Q32)
    lat = [mulq(sat32(tdiv(x << 16, r)), 65536 + 8 * W.knorm[i]) for i, x in enumerate(latr)]
    e_lat = choose_e(lat); lat_u = quant(lat, e_lat)
    kc, v = proj(W, "wk_c", lat_u, e_lat), proj(W, "wv", lat_u, e_lat)
    cache = st["cache"]
    if len(cache) >= MAX_SEQ: raise OverflowError("KV cache full: sequence must restart")
    cache.append(kc + kr + v)
    T = len(cache)
    score, p, ctx = [], [], []
    for hd in range(H):
        q = qc[hd * DK:(hd + 1) * DK] + qr[hd * DR:(hd + 1) * DR]
        sc = []
        for row in cache:
            k = row[hd * DK:(hd + 1) * DK] + row[H * DK:H * DK + DR]
            sc.append(mulq(sat32(sum(a * b for a, b in zip(q, k)) >> 16), INV_SQRT_QK))
        m = max(sc); ex = [exp_neg_q(m - s) for s in sc]; tot = sum(ex)
        ph = [(x << 16) // tot for x in ex]
        for j in range(DV):
            c = H * DK + DR + hd * DV + j
            ctx.append(sat32(sum(pt * row[c] for pt, row in zip(ph, cache)) >> 16))
        score += sc; p += ph
    e_ctx = choose_e(ctx); ctx_u = quant(ctx, e_ctx)
    out = proj(W, "o", ctx_u, e_ctx)
    return dict(hu=hu, he=he, latr=latr, lat=lat, e_lat=e_lat, latu=lat_u, qc=qc, qr=qr, kr=kr,
                kc=kc, v=v, score=score, p=p, ctx=ctx, e_ctx=e_ctx, ctxu=ctx_u, out=out, T=T)

def cache_words(st):
    """Expected 64-bit SRAM image of the valid cache entries (word = pos*72 + w)."""
    return [((row[2 * w + 1] & 0xffffffff) << 32) | (row[2 * w] & 0xffffffff)
            for row in st["cache"] for w in range(WORDS)]

# ------------------------------------------------------------------ hex gen --
def gen_hex(wdir, group=128):
    """Write the MLA weight ROM images from the official generator (numpy)."""
    import nano_ref
    Wf = nano_ref.official_weights(group)
    os.makedirs(wdir, exist_ok=True)
    q, s, z = [], [], []
    for n, k, o in MATS:
        pk, sc, zp = Wf[f"L1.mla.{n}.q"], Wf[f"L1.mla.{n}.s"], Wf[f"L1.mla.{n}.z"]
        assert pk.shape == (k // 2, o) and sc.shape == (k // min(group, k), o) == zp.shape
        q += [int(x) for x in pk.reshape(-1)]; s += [int(x) for x in sc.reshape(-1)]
        z += [int(x) for x in zp.reshape(-1)]
    kn = [int(x) for x in Wf["L1.mla.knorm.w"]]
    for name, vals, fmt in (("q", q, "{:02x}"), ("s", s, "{:04x}"), ("z", z, "{:02x}"),
                            ("knorm", kn, "{:04x}")):
        with open(os.path.join(wdir, name + ".hex"), "w") as f:
            f.write("\n".join(fmt.format(v & 0xffff) for v in vals) + "\n")

def gen_luts_vh():
    lines = ["// Generated by mla_model.py gen_luts_vh(); do not edit.",
             "// exp(-i/32) in Q16 for i = 0..512 (MLA softmax).",
             "function signed [31:0] expn_tab; input integer i; begin case (i)"]
    lines += [f"  {i}: expn_tab = {v};" for i, v in enumerate(EXPN)]
    lines += ["  default: expn_tab = 0; endcase end endfunction", ""]
    return "\n".join(lines)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "luts":
        out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "mla_luts.vh")
        open(out, "w").write(gen_luts_vh())
    elif len(sys.argv) > 1 and sys.argv[1] == "hex":
        gen_hex(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 128)
