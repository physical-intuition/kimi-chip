#!/usr/bin/env python3
"""Bit-exact integer model of the KDA datapath plus a float64 reference.
X4Y4 changes vs X4Y3 (both found by checking against reference/model.py via
nano_ref.py): the f/z low-rank width is kda_dim = 32 (X4Y3 used 8), and the
gated RMSNorm uses RMS_EPS = 1e-5 (X4Y3 used the L2 eps 1e-6).

Number format: every activation/state value is a signed 32-bit Q16.16 integer
(saturating). Products are floor((a*b) / 2^16). INT4 weights are deterministic
placeholders (group-128 dequant stubbed as a fixed 2^-6 scale); the KDA input
x is a deterministic placeholder INT8 embedding of token_id (scale 2^-5).
The RTL (dataflow_top.v) must match int_step() exactly; float_step() shows the
quantization/LUT approximation error against exact real-valued math.
"""
import math

H, DH, P, R = 2, 32, 64, 32           # heads, head dim, H*DH, low-rank f/z dim (= kda_dim)
FRAC = 16
EPS_Q32 = round(1e-6 * 2**32)          # L2-norm eps in Q32 (units of x^2)
RMS_EPS_Q32 = round(1e-5 * 2**32)      # RMSNorm eps in Q32
INV_SQRT_DH = round(65536 / math.sqrt(DH))
A_Q88 = [256, 384]                     # A_h = exp(A_log) as unsigned Q8.8
NOUT = {0: P, 1: P, 2: P, 3: H, 4: R, 5: P, 6: R, 7: P, 8: P}
NIN = {0: P, 1: P, 2: P, 3: P, 4: P, 5: R, 6: P, 7: R, 8: P}
NAMES = {0: "q", 1: "k", 2: "v", 3: "beta", 4: "f1", 5: "f2", 6: "z1", 7: "z2", 8: "o"}

SIG = [round(65536 / (1 + math.exp(-(-8 + i / 16)))) for i in range(257)]
EXP5 = [round(65536 * math.exp(-5 * i / 256)) for i in range(257)]

def sat32(x): return max(-2**31, min(2**31 - 1, x))
def sat8(x): return max(-128, min(127, x))
def mulq(a, b): return sat32((a * b) >> FRAC)
def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q

def sigmoid_q(x):
    xc = max(-524288, min(524287, x))
    off = xc + 524288
    i, fr = off >> 12, off & 4095
    return SIG[i] + (((SIG[i + 1] - SIG[i]) * fr) >> 12)

def exp5_q(s):                          # exp(-5*s), s in Q16 [0, 1]
    i, fr = s >> 8, s & 255
    if i >= 256: return EXP5[256]
    return EXP5[i] + (((EXP5[i + 1] - EXP5[i]) * fr) >> 8)

def w_u(m, o, i):                       # unsigned INT4 code; weight = code - 8
    return (m * 131 + o * 67 + i * 29 + ((o * i) % 13) * 7) & 15
def x_u(t, i):                          # unsigned INT8 code; x = code - 128
    return (t * 73 + i * 151 + ((t ^ i) & 31) * 5) & 255
def conv_w(c, j):                       # Q16 depthwise taps in [-0.5, 0.5]
    return (((c * 7 + j * 3) % 9) - 4) << 13
def dt_bias(c): return (((c * 13) % 17) - 8) << 12
def onorm(j): return 65536 + ((((j * 5) % 7) - 3) << 12)

def proj(m, src_u):
    return [sum((src_u[i] - 128) * (w_u(m, o, i) - 8) for i in range(NIN[m]))
            for o in range(NOUT[m])]

def delta_update(Sh, kh, vh, beta_h):
    """Per value column j: u = v - k.S[:,j]; S[:,j] += (beta*k) * u."""
    for j in range(DH):
        ks = sat32(sum(kh[i] * Sh[i][j] for i in range(DH)) >> 16)
        u = sat32(vh[j] - ks)
        for i in range(DH):
            Sh[i][j] = sat32(Sh[i][j] + mulq(mulq(beta_h, kh[i]), u))

def new_state():
    return dict(hist=[[0] * 192 for _ in range(3)],      # hist[tap][stream*64+c]
                S=[[[0] * DH for _ in range(DH)] for _ in range(H)])

def int_step(st, t):
    xu = [x_u(t, i) for i in range(P)]
    q = [sat32(r << 5) for r in proj(0, xu)]
    k = [sat32(r << 5) for r in proj(1, xu)]
    v = [sat32(r << 5) for r in proj(2, xu)]
    beta_raw = proj(3, xu)
    hf = [sat8(r >> 6) + 128 for r in proj(4, xu)]
    f = [sat32(r << 5) for r in proj(5, hf)]
    hz = [sat8(r >> 6) + 128 for r in proj(6, xu)]
    z = [sat32(r << 5) for r in proj(7, hz)]
    pre = q + k + v
    hist = st["hist"]
    conv = []
    for c in range(192):
        cur, h1, h2, h3 = pre[c], hist[0][c], hist[1][c], hist[2][c]
        y = sat32(mulq(conv_w(c, 0), cur) + mulq(conv_w(c, 1), h1) +
                  mulq(conv_w(c, 2), h2) + mulq(conv_w(c, 3), h3))
        conv.append(mulq(y, sigmoid_q(y)))
        hist[2][c], hist[1][c], hist[0][c] = h2, h1, cur
    q, k, v = conv[0:64], conv[64:128], conv[128:192]
    for vec in (q, k):
        for h in range(H):
            seg = vec[h * DH:(h + 1) * DH]
            r = math.isqrt(sum(x * x for x in seg) + EPS_Q32)
            vec[h * DH:(h + 1) * DH] = [sat32(tdiv(x << 16, r)) for x in seg]
    beta = [sigmoid_q(sat32(b << 5)) for b in beta_raw]
    alpha = []
    for c in range(P):
        a_in = sat32((A_Q88[c // DH] * sat32(f[c] + dt_bias(c))) >> 8)
        alpha.append(exp5_q(sigmoid_q(a_in)))
    S = st["S"]
    o = []
    for h in range(H):
        Sh = S[h]
        for i in range(DH):
            for j in range(DH):
                Sh[i][j] = mulq(Sh[i][j], alpha[h * DH + i])
        kh, qh, vh = k[h*DH:(h+1)*DH], q[h*DH:(h+1)*DH], v[h*DH:(h+1)*DH]
        delta_update(Sh, kh, vh, beta[h])
        for j in range(DH):
            o.append(mulq(sat32(sum(qh[i] * Sh[i][j] for i in range(DH)) >> 16), INV_SQRT_DH))
    y = []
    for h in range(H):
        seg = o[h * DH:(h + 1) * DH]
        rs = math.isqrt((sum(x * x for x in seg) >> 5) + RMS_EPS_Q32)
        for j, x in enumerate(seg):
            n = sat32(tdiv(x << 16, rs))
            y.append(mulq(mulq(n, onorm(j)), sigmoid_q(z[h * DH + j])))
    yu = [sat8(val >> 11) + 128 for val in y]
    out = [sat32(r << 5) for r in proj(8, yu)]
    return dict(pre=pre, q=q, k=k, v=v, beta=beta, alpha=alpha, f=f, z=z,
                attn=o, y=y, out=out, S=[[row[:] for row in Sh] for Sh in S],
                hist=[h[:] for h in hist])

# ---------------- float64 reference of the same operator math -------------
def float_new_state():
    return dict(hist=[[0.0] * 192 for _ in range(3)],
                S=[[[0.0] * DH for _ in range(DH)] for _ in range(H)])

def float_step(st, t):
    sig = lambda x: 1 / (1 + math.exp(-x))
    xs = [(x_u(t, i) - 128) / 32 for i in range(P)]
    def fp(m, src): return [sum(src[i] * (w_u(m, o, i) - 8) / 64 for i in range(NIN[m])) for o in range(NOUT[m])]
    q, k, v, br = fp(0, xs), fp(1, xs), fp(2, xs), fp(3, xs)
    f, z = fp(5, fp(4, xs)), fp(7, fp(6, xs))
    pre = q + k + v; hist = st["hist"]; conv = []
    for c in range(192):
        y = sum(conv_w(c, j) / 65536 * x for j, x in enumerate([pre[c], hist[0][c], hist[1][c], hist[2][c]]))
        conv.append(y * sig(y))
        hist[2][c], hist[1][c], hist[0][c] = hist[1][c], hist[0][c], pre[c]
    q, k, v = conv[0:64], conv[64:128], conv[128:192]
    for vec in (q, k):
        for h in range(H):
            n = math.sqrt(sum(x * x for x in vec[h*DH:(h+1)*DH]) + 1e-6)
            vec[h*DH:(h+1)*DH] = [x / n for x in vec[h*DH:(h+1)*DH]]
    beta = [sig(b) for b in br]
    alpha = [math.exp(-5 * sig(A_Q88[c // DH] / 256 * (f[c] + dt_bias(c) / 65536))) for c in range(P)]
    S = st["S"]; o = []
    for h in range(H):
        Sh = S[h]
        for i in range(DH):
            for j in range(DH): Sh[i][j] *= alpha[h*DH+i]
        for j in range(DH):
            u = v[h*DH+j] - sum(k[h*DH+i] * Sh[i][j] for i in range(DH))
            for i in range(DH): Sh[i][j] += beta[h] * k[h*DH+i] * u
        for j in range(DH):
            o.append(sum(q[h*DH+i] * Sh[i][j] for i in range(DH)) / math.sqrt(DH))
    y = []
    for h in range(H):
        seg = o[h*DH:(h+1)*DH]; rms = math.sqrt(sum(x*x for x in seg) / DH + 1e-5)
        y += [x / rms * onorm(j) / 65536 * sig(z[h*DH+j]) for j, x in enumerate(seg)]
    return dict(q=q, k=k, v=v, beta=beta, alpha=alpha, attn=o, y=y,
                S=[[row[:] for row in Sh] for Sh in S])

def gen_luts_vh():
    lines = ["// Generated by kda_model.py gen_luts_vh(); do not edit.",
             "function signed [31:0] sig_tab; input integer i; begin case (i)"]
    lines += [f"  {i}: sig_tab = {v};" for i, v in enumerate(SIG)]
    lines += ["  default: sig_tab = 0; endcase end endfunction",
              "function signed [31:0] exp5_tab; input integer i; begin case (i)"]
    lines += [f"  {i}: exp5_tab = {v};" for i, v in enumerate(EXP5)]
    lines += ["  default: exp5_tab = 0; endcase end endfunction", ""]
    return "\n".join(lines)

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "luts":
        open("kda_luts.vh", "w").write(gen_luts_vh())
