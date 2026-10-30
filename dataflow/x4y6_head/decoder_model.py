#!/usr/bin/env python3
"""Bit-exact integer model of the X4Y6 decoder datapath: the whole of
reference/model.py RefModel.step -- embedding lookup (official INT4 emb table),
L0 (KDA) and L1 (MLA) with RMSNorm, attention-residual mixing and MoE, the final
res_out mix, final RMSNorm, untied LM head (512 logits) and argmax (strict
greater scan: lowest index wins ties, like np.argmax).
(X4Y5 docstring follows.)

Normative math (reference/model.py RefModel.step, attn_res_block = 2):

  L0 (KDA, block boundary): blocks = [x0]
      a0  = KDA(RMSNorm(x0, L0.norm1))
      x   = res_mix([x0, a0], L0.res_mlp)
      x1  = a0 + MoE0(RMSNorm(x, L0.norm2))                      (L0.out)
  L1 (MLA, inside block 0):
      x   = res_mix([x0, x1], L1.res_attn)
      pre = x1 + MLA(RMSNorm(x, L1.norm1))
      x   = res_mix([x0, pre], L1.res_mlp)
      x2  = pre + MoE1(RMSNorm(x, L1.norm2))                     (L1.out)

  res_mix(cands, P): logit_c = RMSNorm(c, P.norm) . P.proj, p = softmax(logits),
      out = sum_c p_c * c (raw candidates).
  MoE: s = sigmoid(h @ router); top-2 by s + bias (bias only selects; ties to the
      lowest index); w = s_sel / sum(s_sel) * 2.828; out = shared(h) +
      sum_j w_j * expert_j(h), expert(h) = (silu(h @ g) * (h @ u)) @ d.

Number formats (chip choice, docs/quantization.md conventions of X4Y3/X4Y4):
  * activations Q16.16 int32, saturating; mulq = floor(a*b / 2^16).
  * RMSNorm: r = isqrt(floor(sum x^2 / d) + round(1e-5 * 2^32)) (Q16),
    y = mulq(sat32(trunc(x*2^16 / r)), 65536 + 8*w) for an n16 offset w.
  * res_mix: logit = sat32(floor(sum y_i * proj_i / 2^11)) (proj a16 = Q4.11),
    softmax with the X4Y4 513-entry exp LUT, p_c = floor(ex_c * 2^16 / sum ex),
    out = sat32(floor((p0*c0 + p1*c1) / 2^16)).
  * every matmul input is an INT8 code vector with a per-vector exponent
    e = choose_e (X4Y4 rule); reference int4 weights (q - z) * s * 2^-12.
  * KDA (X4Y3 placeholder weights, fixed z = 8 / s = 64) takes its input codes
    with the same per-vector exponent e (X4Y3/X4Y4 hardwired e = 11).
  * MoE: router logits Q16 -> sigmoid LUT (X4Y3) -> key = s + bias*2^5;
    top-2 strict-greater scan (lowest index wins ties);
    w = floor(s * RS / (s_a + s_b)), RS = round(2.828 * 2^16);
    act = mulq(mulq(g, sigmoid(g)), u) -> INT8 codes (choose_e) -> d;
    out = shared; out = sadd(out, mulq(w_a, d_a)); out = sadd(out, mulq(w_b, d_b)).
  * The layer input x0 is STAGED: a deterministic placeholder embedding
    x0_i = (kda_model.x_u(t, i) - 128) * 2^7 (Q16, std ~0.14 like the official
    embedding table). The embedding ROM lookup is X4Y6.
"""
import math, os, sys
import kda_model as km
import mla_model as mm

D, DFF, NE, TOPK = 64, 32, 8, 2
RMS_EPS_Q32 = round(1e-5 * 2**32)
RS = round(2.828 * 65536)
HERE = os.path.dirname(os.path.abspath(__file__))

sat32, sat8, mulq, tdiv = mm.sat32, mm.sat8, mm.mulq, mm.tdiv
choose_e, quant, exp_neg_q = mm.choose_e, mm.quant, mm.exp_neg_q
sigmoid_q = km.sigmoid_q
def sadd(a, b): return sat32(a + b)

def emb_q(t, i): return (km.x_u(t, i) - 128) << 7          # X4Y5 STAGED placeholder (history only)
VOCAB = 512
# Embedding row t (reference dequant_emb): w = (q - z) * s * 2^-12, so Q16.16 is
# exactly (q - z) * s * 16. Groups along d_model, group = min(group_size, 64).
def emb(W, t):
    g = min(W.group, D); ng = D // g
    out = []
    for i in range(D):
        b = W.embq[t * (D // 2) + (i >> 1)]
        q = (b >> 4) if i & 1 else (b & 15)
        out.append(sat32((q - W.embz[t * ng + i // g]) * W.embs[t * ng + i // g] * 16))
    return out

# ---- weight ROM layout (per layer; layer l at l * stride) ----------------------
# MoE matrices, kind k: 0 router (64x8), 1 g (64x32), 2 u (64x32), 3 d (32x64);
# expert slot x: 0..7 routed, 8 shared.
def moe_shape(k): return {0: (D, NE), 1: (D, DFF), 2: (D, DFF), 3: (DFF, D)}[k]
def moe_layout(group):
    """Byte/scale offsets in the flat MoE ROMs: (qoff(k, x), soff(k, x), qstride, sstride)."""
    def nq(k): kk, n = moe_shape(k); return kk // 2 * n
    def ns(k): kk, n = moe_shape(k); return kk // min(group, kk) * n
    qslot = nq(1) + nq(2) + nq(3); sslot = ns(1) + ns(2) + ns(3)
    def qoff(k, x):
        if k == 0: return 0
        return nq(0) + x * qslot + sum(nq(j) for j in range(1, k))
    def soff(k, x):
        if k == 0: return 0
        return ns(0) + x * sslot + sum(ns(j) for j in range(1, k))
    return qoff, soff, nq(0) + 9 * qslot, ns(0) + 9 * sslot

# small int16 params per layer (SMALL_N words, layer l at l * SMALL_N)
SMALL = dict(ra_norm=0, ra_proj=64, norm1=128, rm_norm=192, rm_proj=256, norm2=320, bias=384)
SMALL_N = 392
# X4Y6 output params after the two layers, at 2 * SMALL_N
SMALL_OUT = dict(out_norm=0, out_proj=64, fnorm=128)
SMALL_OUT_N = 192
SMALL_NAMES = [("ra_norm", "res_attn.norm.w"), ("ra_proj", "res_attn.proj"), ("norm1", "norm1.w"),
               ("rm_norm", "res_mlp.norm.w"), ("rm_proj", "res_mlp.proj"), ("norm2", "norm2.w"),
               ("bias", "moe.bias")]

def read_hex(path, bits):
    vals = [int(l, 16) for l in open(path) if l.strip()]
    return [v - (1 << bits) if v >> (bits - 1) else v for v in vals] if bits == 16 else vals

class Weights:
    def __init__(self, wdir=os.path.join(HERE, "glue_weights"), group=128):
        self.group = group
        self.qoff, self.soff, self.qstride, self.sstride = moe_layout(group)
        self.qrom = read_hex(os.path.join(wdir, "moe_q.hex"), 8)
        self.srom = read_hex(os.path.join(wdir, "moe_s.hex"), 16)
        self.zrom = read_hex(os.path.join(wdir, "moe_z.hex"), 8)
        self.small = read_hex(os.path.join(wdir, "small.hex"), 16)
        assert len(self.qrom) == 2 * self.qstride and len(self.srom) == 2 * self.sstride == len(self.zrom)
        assert len(self.small) == 2 * SMALL_N + SMALL_OUT_N
        g = min(group, D)
        self.embq = read_hex(os.path.join(wdir, "emb_q.hex"), 8)
        self.embs = read_hex(os.path.join(wdir, "emb_s.hex"), 16)
        self.embz = read_hex(os.path.join(wdir, "emb_z.hex"), 8)
        self.headq = read_hex(os.path.join(wdir, "head_q.hex"), 8)
        self.heads = read_hex(os.path.join(wdir, "head_s.hex"), 16)
        self.headz = read_hex(os.path.join(wdir, "head_z.hex"), 8)
        assert len(self.embq) == VOCAB * D // 2 and len(self.embs) == VOCAB * (D // g) == len(self.embz)
        assert len(self.headq) == D // 2 * VOCAB and len(self.heads) == D // g * VOCAB == len(self.headz)
        self.mla = mm.Weights(os.path.join(wdir, "mla"), group)
    def sp(self, l, name, i): return self.small[l * SMALL_N + SMALL[name] + i]
    def op(self, name, i): return self.small[2 * SMALL_N + SMALL_OUT[name] + i]

def moe_proj(W, l, k, x, codes, e):
    kk, n = moe_shape(k); g = min(W.group, kk); assert len(codes) == kk
    qb = l * W.qstride + W.qoff(k, x); sb = l * W.sstride + W.soff(k, x)
    out = []
    for o in range(n):
        acc = 0
        for gi in range(kk // g):
            z = W.zrom[sb + gi * n + o]
            raw = 0
            for i in range(gi * g, (gi + 1) * g):
                b = W.qrom[qb + (i >> 1) * n + o]
                raw += (codes[i] - 128) * (((b >> 4) if i & 1 else (b & 15)) - z)
            acc += raw * W.srom[sb + gi * n + o]
        out.append(sat32(acc >> (12 - e) if e <= 12 else acc << (e - 12)))
    return out

# ---- glue operators --------------------------------------------------------------
def rms_root(x): return math.isqrt((sum(v * v for v in x) >> 6) + RMS_EPS_Q32)
def rmsnorm(x, gain16):
    r = rms_root(x)
    return [mulq(sat32(tdiv(v << 16, r)), 65536 + 8 * w) for v, w in zip(x, gain16)]

def res_mix(W, l, pfx, cands, norm=None, proj=None):
    if norm is None:
        norm = [W.sp(l, pfx + "_norm", i) for i in range(D)]
        proj = [W.sp(l, pfx + "_proj", i) for i in range(D)]
    logits = [sat32(sum(y * p for y, p in zip(rmsnorm(c, norm), proj)) >> 11) for c in cands]
    m = max(logits); ex = [exp_neg_q(m - v) for v in logits]; tot = sum(ex)
    p = [(v << 16) // tot for v in ex]
    out = [sat32((p[0] * a + p[1] * b) >> 16) for a, b in zip(*cands)]
    return dict(logits=logits, p=p, out=out)

def top2(keys):
    a = 0
    for j in range(1, NE):
        if keys[j] > keys[a]: a = j
    b = 1 if a == 0 else 0
    for j in range(NE):
        if j != a and keys[j] > keys[b]: b = j
    return a, b

def moe(W, l, h):
    e = choose_e(h); hu = quant(h, e)
    r = moe_proj(W, l, 0, 0, hu, e)
    s = [sigmoid_q(v) for v in r]
    keys = [sat32(v + (W.sp(l, "bias", j) << 5)) for j, v in enumerate(s)]
    a, b = top2(keys)
    w = [(s[a] * RS) // (s[a] + s[b]), (s[b] * RS) // (s[a] + s[b])]
    slots, out = [], None
    for slot, x in enumerate((8, a, b)):
        g = moe_proj(W, l, 1, x, hu, e); u = moe_proj(W, l, 2, x, hu, e)
        act = [mulq(mulq(gv, sigmoid_q(gv)), uv) for gv, uv in zip(g, u)]
        ea = choose_e(act); au = quant(act, ea)
        d = moe_proj(W, l, 3, x, au, ea)
        out = d if slot == 0 else [sadd(o, mulq(w[slot - 1], dv)) for o, dv in zip(out, d)]
        slots.append(dict(x=x, g=g, u=u, act=act, ea=ea, au=au, d=d, acc=out[:]))
    return dict(e=e, hu=hu, r=r, s=s, keys=keys, sel=[a, b], w=w, slots=slots, out=out)

def head_proj(W, codes, e):
    """LM head (64 -> 512), reference standard int4 layout, same arithmetic as moe_proj."""
    g = min(W.group, D); out = []
    for o in range(VOCAB):
        acc = 0
        for gi in range(D // g):
            z = W.headz[gi * VOCAB + o]; raw = 0
            for i in range(gi * g, (gi + 1) * g):
                b = W.headq[(i >> 1) * VOCAB + o]
                raw += (codes[i] - 128) * (((b >> 4) if i & 1 else (b & 15)) - z)
            acc += raw * W.heads[gi * VOCAB + o]
        out.append(sat32(acc >> (12 - e) if e <= 12 else acc << (e - 12)))
    return out

def argmax(v):
    a = 0
    for j in range(1, len(v)):
        if v[j] > v[a]: a = j
    return a

def new_state(): return dict(kda=km.new_state(), mla=mm.new_state())

def int_step(W, st, t):
    """One token through L0 and L1. Returns every intermediate (see GLUE_* below)."""
    x0 = emb(W, t)
    g = {}
    g[0] = rmsnorm(x0, [W.sp(0, "norm1", i) for i in range(D)])          # h0
    kda_e = choose_e(g[0]); kda_u = quant(g[0], kda_e)
    kda = km.int_step(st["kda"], t, xu=kda_u, ex=kda_e)
    a0 = kda["out"]
    m0 = res_mix(W, 0, "rm", [x0, a0])
    h = rmsnorm(m0["out"], [W.sp(0, "norm2", i) for i in range(D)])
    moe0 = moe(W, 0, h)
    x1 = [sadd(p, q) for p, q in zip(a0, moe0["out"])]
    m1 = res_mix(W, 1, "ra", [x0, x1])
    h1 = rmsnorm(m1["out"], [W.sp(1, "norm1", i) for i in range(D)])
    mla_e = choose_e(h1); mla_u = quant(h1, mla_e)
    mla = mm.int_step(W.mla, st["mla"], t, hu=mla_u, he=mla_e)
    pre = [sadd(p, q) for p, q in zip(x1, mla["out"])]
    m2 = res_mix(W, 1, "rm", [x0, pre])
    h2 = rmsnorm(m2["out"], [W.sp(1, "norm2", i) for i in range(D)])
    moe1 = moe(W, 1, h2)
    x2 = [sadd(p, q) for p, q in zip(pre, moe1["out"])]
    m3 = res_mix(W, None, None, [x0, x2], norm=[W.op("out_norm", i) for i in range(D)],
                 proj=[W.op("out_proj", i) for i in range(D)])
    hn = rmsnorm(m3["out"], [W.op("fnorm", i) for i in range(D)])
    head_e = choose_e(hn); head_u = quant(hn, head_e)
    logits = head_proj(W, head_u, head_e)
    return dict(mix3=m3, hn=hn, head_e=head_e, head_u=head_u, logits=logits, argmax=argmax(logits),
                x0=x0, h0=g[0], kda_e=kda_e, kda_u=kda_u, kda=kda, a0=a0, mix0=m0, h0b=h,
                moe0=moe0, x1=x1, mix1=m1, h1=h1, mla_e=mla_e, mla_u=mla_u, mla=mla, pre=pre,
                mix2=m2, h2=h2, moe1=moe1, x2=x2)

# ---- hex generation from the official generator --------------------------------
def gen_hex(wdir, group=128):
    import nano_ref
    Wf = nano_ref.official_weights(group)
    qoff, soff, qstride, sstride = moe_layout(group)
    q, s, z = [0] * (2 * qstride), [0] * (2 * sstride), [0] * (2 * sstride)
    for l in range(2):
        for k in range(4):
            for x in ([0] if k == 0 else range(9)):
                nm = f"L{l}.moe." + ("router" if k == 0 else ("shared." if x == 8 else f"e{x}.") + "gud"[k - 1])
                pk, sc, zp = Wf[nm + ".q"], Wf[nm + ".s"], Wf[nm + ".z"]
                kk, n = moe_shape(k)
                assert pk.shape == (kk // 2, n) and sc.shape == (kk // min(group, kk), n) == zp.shape, nm
                qb, sb = l * qstride + qoff(k, x), l * sstride + soff(k, x)
                for i, v in enumerate(pk.reshape(-1)): q[qb + i] = int(v)
                for i, (a, b) in enumerate(zip(sc.reshape(-1), zp.reshape(-1))):
                    s[sb + i] = int(a); z[sb + i] = int(b)
    small = []
    for l in range(2):
        for key, nm in SMALL_NAMES:
            v = [int(x) for x in Wf[f"L{l}.{nm}"].reshape(-1)]
            assert len(v) == (8 if key == "bias" else 64), nm
            small += v
    for nm in ("res_out.norm.w", "res_out.proj", "final_norm.w"):
        v = [int(x) for x in Wf[nm].reshape(-1)]; assert len(v) == 64, nm; small += v
    g = min(group, D)
    for nm, shp in (("emb", ((VOCAB, D // 2), (VOCAB, D // g))), ("head", ((D // 2, VOCAB), (D // g, VOCAB)))):
        pk, sc, zp = Wf[nm + ".q"], Wf[nm + ".s"], Wf[nm + ".z"]
        assert pk.shape == shp[0] and sc.shape == shp[1] == zp.shape, nm
        for name, vals, fmt in ((nm + "_q", pk, "{:02x}"), (nm + "_s", sc, "{:04x}"), (nm + "_z", zp, "{:02x}")):
            os.makedirs(wdir, exist_ok=True)
            with open(os.path.join(wdir, name + ".hex"), "w") as f:
                f.write("\n".join(fmt.format(int(v) & 0xffff) for v in vals.reshape(-1)) + "\n")
    os.makedirs(wdir, exist_ok=True)
    for name, vals, fmt in (("moe_q", q, "{:02x}"), ("moe_s", s, "{:04x}"), ("moe_z", z, "{:02x}"),
                            ("small", small, "{:04x}")):
        with open(os.path.join(wdir, name + ".hex"), "w") as f:
            f.write("\n".join(fmt.format(v & 0xffff) for v in vals) + "\n")
    mm.gen_hex(os.path.join(wdir, "mla"), group)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "hex":
        gen_hex(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 128)
