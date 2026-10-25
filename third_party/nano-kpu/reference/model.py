"""NORMATIVE reference implementation of the Moonshot hybrid text stack
(float32, weights dequantized from the packed int4 image format).

Correctness for the chip is judged by COSINE SIMILARITY against this
model's per-position logits (pass bar: cos >= 0.98 on every row, see
harness/scoring.py) — the chip's internal number formats are free.
Where prose documentation and this code disagree, THIS CODE WINS.

Execution model: strictly token-by-token (recurrent/causal). The evaluation
is teacher-forced: the chip receives the whole token sequence and must emit
logits and argmax for every position, maintaining its KV cache / KDA state
exactly as a decoder would. The attention-residual snapshots are
per-position (no cross-token state).
"""

import numpy as np

from .config import (ModelConfig, RMS_EPS, L2_EPS, KDA_GATE_LOWER_BOUND,
                     ROUTER_SCALE)

F32 = np.float32


# ---------------------------------------------------------------- dequant --

def unpack_int4(packed: np.ndarray, k: int, n: int) -> np.ndarray:
    """packed: uint8 [k//2, n], two int4 values per byte along the INPUT
    dimension: byte b at row r holds w[2r] in bits[3:0], w[2r+1] in bits
    [7:4]. Returns uint8 [k, n] with values 0..15."""
    p = packed.reshape(k // 2, n)
    out = np.empty((k, n), dtype=np.uint8)
    out[0::2] = p & 0x0F
    out[1::2] = p >> 4
    return out


def dequant_w4(packed, scales, zeros, k, n, group) -> np.ndarray:
    """w[i,j] = (q[i,j] - zeros[i//group, j]) * scales[i//group, j] * 2^-12
    scales: int16 [k/group, n] (Q3.12), zeros: uint8 [k/group, n] (0..15).
    group is clamped to k. Result float32 [k, n]."""
    group = min(group, k)
    q = unpack_int4(packed, k, n).astype(np.int32)
    g = np.arange(k) // group
    s = scales.astype(np.int32)[g] * F32(2.0 ** -12)
    z = zeros.astype(np.int32)[g]
    return ((q - z).astype(F32) * s.astype(F32)).astype(F32)


def dequant_emb(packed, scales, zeros, vocab, d, group) -> np.ndarray:
    """Embedding table, token-major: packed uint8 [vocab, d//2] (byte j of
    row t holds w[t,2j] in bits[3:0], w[t,2j+1] in bits[7:4]); per-row
    groups along d: scales int16 [vocab, d/group] (Q3.12), zeros uint8 same
    shape. w[t,i] = (q[t,i] - z[t,i//g]) * s[t,i//g] * 2^-12.
    Result float32 [vocab, d]."""
    group = min(group, d)
    p = packed.reshape(vocab, d // 2)
    q = np.empty((vocab, d), dtype=np.uint8)
    q[:, 0::2] = p & 0x0F
    q[:, 1::2] = p >> 4
    g = np.arange(d) // group
    s = scales.astype(np.int32)[:, g] * F32(2.0 ** -12)
    z = zeros.astype(np.int32)[:, g]
    return ((q.astype(np.int32) - z).astype(F32) * s.astype(F32)).astype(F32)


# ---------------------------------------------------------------- helpers --

def rmsnorm(x, w, eps=RMS_EPS):
    """1-centered RMSNorm over the last axis: y = x/rms(x) * (1 + w).
    Norm weights ship as int16 offsets around 1 (docs/quantization.md)."""
    x = x.astype(F32)
    ms = np.mean(x * x, axis=-1, keepdims=True, dtype=F32)
    return (x / np.sqrt(ms + F32(eps)) * (F32(1.0) + w)).astype(F32)


def l2norm(x, eps=L2_EPS):
    n = np.sqrt(np.sum(x * x, axis=-1, keepdims=True, dtype=F32) + F32(eps))
    return (x / n).astype(F32)


def silu(x):
    return (x / (1.0 + np.exp(-x, dtype=F32))).astype(F32)


def sigmoid(x):
    return (1.0 / (1.0 + np.exp(-x, dtype=F32))).astype(F32)


def softmax(x):
    e = np.exp(x - x.max(), dtype=F32)
    return (e / e.sum(dtype=F32)).astype(F32)


# ------------------------------------------------------------ the model ----

class RefModel:
    """weights: dict name -> array as produced by gen_weights.gen_weights
    (packed .q/.s/.z triples for matmul weights, int16 fixed-point small
    params). Dequantization to float happens here, once, at load."""

    def __init__(self, cfg: ModelConfig, weights: dict):
        self.cfg = cfg
        self.w = {}
        for name, (k, n) in matmul_shapes(cfg).items():
            self.w[name] = dequant_w4(
                np.asarray(weights[name + ".q"], np.uint8),
                np.asarray(weights[name + ".s"], np.int64),
                np.asarray(weights[name + ".z"], np.uint8),
                k, n, cfg.group_size)
        self.w["emb"] = dequant_emb(
            np.asarray(weights["emb.q"], np.uint8),
            np.asarray(weights["emb.s"], np.int64),
            np.asarray(weights["emb.z"], np.uint8),
            cfg.vocab, cfg.d_model, cfg.group_size)
        for name, kind in small_params(cfg):
            v = np.asarray(weights[name], np.int64)
            scale = {"n16": 2.0 ** -13, "a16": 2.0 ** -11, "u16": 2.0 ** -8}[kind]
            self.w[name] = (v * scale).astype(F32)
        self.dump = None
        self.reset()

    def reset(self):
        c = self.cfg
        self.pos = 0
        self.kv_k, self.kv_v = {}, {}
        self.kda_state, self.conv_hist = {}, {}
        for i, t in enumerate(c.layer_types):
            if t == "F":
                self.kv_k[i], self.kv_v[i] = [], []
            else:
                self.kda_state[i] = np.zeros(
                    (c.kda_heads, c.kda_dim, c.kda_dim), dtype=F32)
                # separate pre-conv histories for the q, k and v streams
                self.conv_hist[i] = np.zeros(
                    (3, c.conv_kernel - 1, c.kda_heads * c.kda_dim),
                    dtype=F32)

    def _dump(self, key, val):
        if self.dump is not None:
            self.dump[f"p{self.pos}.{key}"] = np.asarray(val, F32).copy()

    # -- attention-residual mixing (per position, no cross-token state) --

    def _res_mix(self, prefix, blocks, name):
        """Softmax-weighted mixture of the residual prefix-sum with the
        block-boundary snapshots. Candidates: blocks (oldest first) then
        prefix. Per candidate v: logit = <rmsnorm(v, norm.w), proj>; the
        mixture combines the RAW candidates."""
        cands = list(blocks) + [prefix]
        nw, pw = self.w[f"{name}.norm.w"], self.w[f"{name}.proj"]
        logits = np.array([rmsnorm(v, nw) @ pw for v in cands], dtype=F32)
        p = softmax(logits)
        self._dump(f"{name}.p", p)
        return sum(p[i] * cands[i] for i in range(len(cands))).astype(F32)

    # -- token mixers --

    def _mla(self, li, h):
        """NoPE multi-head latent attention. q = [qc, qr] per head; k = [kc,
        kr] with kr shared across heads; nothing is rotated."""
        c = self.cfg
        p = f"L{li}.mla."
        lat = rmsnorm(h @ self.w[p + "wc"], self.w[p + "knorm.w"])
        qc = (h @ self.w[p + "wq_c"]).reshape(c.n_heads, c.mla_dk)
        qr = (h @ self.w[p + "wq_r"]).reshape(c.n_heads, c.mla_dr)
        kc = (lat @ self.w[p + "wk_c"]).reshape(c.n_heads, c.mla_dk)
        kr = h @ self.w[p + "wk_r"]                       # [dr], shared
        v = (lat @ self.w[p + "wv"]).reshape(c.n_heads, c.mla_dv)
        q = np.concatenate([qc, qr], axis=-1)
        k = np.concatenate([kc, np.broadcast_to(kr, (c.n_heads, c.mla_dr))],
                           axis=-1)
        self.kv_k[li].append(k.astype(F32))
        self.kv_v[li].append(v.astype(F32))
        K = np.stack(self.kv_k[li])              # [T, H, dk+dr]
        V = np.stack(self.kv_v[li])              # [T, H, dv]
        scale = F32(1.0 / np.sqrt(c.mla_dk + c.mla_dr))
        outs = []
        for hd in range(c.n_heads):
            pr = softmax((K[:, hd, :] @ q[hd]) * scale)
            outs.append(pr @ V[:, hd, :])
        self._dump(f"L{li}.mla.ctx", np.stack(outs))
        return (np.concatenate(outs) @ self.w[p + "o"]).astype(F32)

    def _conv(self, li, stream, x):
        """Causal depthwise conv (kernel 4) over the pre-conv history of one
        projection stream (0=q, 1=k, 2=v), then SiLU."""
        c = self.cfg
        w = self.w[f"L{li}.kda.{'qkv'[stream]}conv"]      # [H*dh, K]
        hist = self.conv_hist[li][stream]
        win = np.concatenate([hist, x[None, :]], axis=0)  # [K, H*dh]
        y = silu((win.T * w).sum(axis=-1, dtype=F32))
        self.conv_hist[li][stream] = np.concatenate(
            [hist[1:], x[None, :]], axis=0)
        return y

    def _kda(self, li, h):
        """Kimi Delta Attention: delta rule with a per-key-channel decay.
        Decay is applied to the state BEFORE the delta correction; the
        readout uses the updated state."""
        c = self.cfg
        H, dh = c.kda_heads, c.kda_dim
        p = f"L{li}.kda."
        q = self._conv(li, 0, h @ self.w[p + "q"])
        k = self._conv(li, 1, h @ self.w[p + "k"])
        v = self._conv(li, 2, h @ self.w[p + "v"])
        beta = sigmoid(h @ self.w[p + "b"])               # [H]
        f = ((h @ self.w[p + "f1"]) @ self.w[p + "f2"]).reshape(H, dh)
        # per-channel log-decay, bounded in (KDA_GATE_LOWER_BOUND, 0)
        alpha = np.exp(F32(KDA_GATE_LOWER_BOUND) * sigmoid(
            self.w[p + "A"][:, None] * (f + self.w[p + "dtb"].reshape(H, dh))),
            dtype=F32)
        z = ((h @ self.w[p + "g1"]) @ self.w[p + "g2"]).reshape(H, dh)
        scale = F32(1.0 / np.sqrt(dh))
        outs = []
        for hd in range(H):
            qh = l2norm(q[hd * dh:(hd + 1) * dh])
            kh = l2norm(k[hd * dh:(hd + 1) * dh])
            vh = v[hd * dh:(hd + 1) * dh]
            S = alpha[hd][:, None] * self.kda_state[li][hd]   # [dh, dh]
            u = vh - kh @ S                     # delta (k.S = sum_i k_i S[i,:])
            S = S + np.outer(kh * beta[hd], u).astype(F32)
            self.kda_state[li][hd] = S.astype(F32)
            o = (qh @ S) * scale
            on = rmsnorm(o, self.w[p + "onorm.w"])   # weight shared per head
            outs.append(on * sigmoid(z[hd]))
        self._dump(f"L{li}.kda.core", np.stack(outs))
        return (np.concatenate(outs).astype(F32) @ self.w[p + "o"]).astype(F32)

    # -- MoE MLP --

    def _swiglu(self, h, pref):
        g = h @ self.w[pref + "g"]
        u = h @ self.w[pref + "u"]
        return ((silu(g) * u) @ self.w[pref + "d"]).astype(F32)

    def _moe(self, li, h):
        """Sigmoid router with score-correction bias: the bias biases the
        top-k SELECTION only; mixture weights are the raw sigmoid scores of
        the selected experts, renormalized to sum 1 and scaled by
        ROUTER_SCALE. Ties break to the lowest expert index. One shared
        expert is always added, unweighted."""
        c = self.cfg
        p = f"L{li}.moe."
        scores = sigmoid(h @ self.w[p + "router"])        # [E]
        sel = np.argsort(-(scores + self.w[p + "bias"]),
                         kind="stable")[:c.top_k]
        wsel = scores[sel]
        wsel = (wsel / wsel.sum(dtype=F32) * F32(ROUTER_SCALE)).astype(F32)
        self._dump(f"L{li}.moe.sel", np.stack([sel.astype(F32), wsel]))
        out = self._swiglu(h, p + "shared.")
        for j, wj in zip(sel, wsel):
            out = out + wj * self._swiglu(h, p + f"e{j}.")
        return out.astype(F32)

    # -- one token --

    def step(self, token: int) -> np.ndarray:
        c = self.cfg
        assert self.pos < c.max_seq
        x = self.w["emb"][token].astype(F32)
        blocks = []          # attention-residual snapshots (this position)
        for li, t in enumerate(c.layer_types):
            boundary = li % c.attn_res_block == 0
            prefix = x
            if boundary:
                blocks.append(x)
            mix_in = blocks[:-1] if boundary else blocks
            if mix_in:
                x = self._res_mix(x, mix_in, f"L{li}.res_attn")
            a = (self._mla if t == "F" else self._kda)(
                li, rmsnorm(x, self.w[f"L{li}.norm1.w"]))
            prefix = a if boundary else (prefix + a).astype(F32)
            x = self._res_mix(prefix, blocks, f"L{li}.res_mlp")
            m = self._moe(li, rmsnorm(x, self.w[f"L{li}.norm2.w"]))
            x = (prefix + m).astype(F32)
            self._dump(f"L{li}.out", x)
        x = self._res_mix(x, blocks, "res_out")
        hn = rmsnorm(x, self.w["final_norm.w"])
        logits = (hn @ self.w["head"]).astype(F32)        # untied LM head
        self.pos += 1
        return logits

    def forward_sequence(self, tokens):
        """Teacher-forced pass. Returns (logits float32 [T, vocab],
        argmax int64 [T]); argmax ties break to the lowest index."""
        self.reset()
        rows = [self.step(int(t)) for t in tokens]
        L = np.stack(rows)
        return L, np.argmax(L, axis=-1).astype(np.int64)


# canonical tensor enumeration (shared with gen_weights / memmap) -----------

def matmul_shapes(c: ModelConfig) -> dict:
    """name -> (fan_in, fan_out) for every standard int4-packed matmul
    weight (packed along fan_in; groups along fan_in, per out channel).
    The embedding `emb` is NOT here — it uses the token-major layout of
    dequant_emb. The LM head IS here (untied, standard layout)."""
    kd = c.kda_heads * c.kda_dim
    out = {}
    for i, t in enumerate(c.layer_types):
        p = f"L{i}."
        if t == "F":
            out[p + "mla.wc"] = (c.d_model, c.mla_dc)
            out[p + "mla.wq_c"] = (c.d_model, c.n_heads * c.mla_dk)
            out[p + "mla.wq_r"] = (c.d_model, c.n_heads * c.mla_dr)
            out[p + "mla.wk_c"] = (c.mla_dc, c.n_heads * c.mla_dk)
            out[p + "mla.wk_r"] = (c.d_model, c.mla_dr)
            out[p + "mla.wv"] = (c.mla_dc, c.n_heads * c.mla_dv)
            out[p + "mla.o"] = (c.n_heads * c.mla_dv, c.d_model)
        else:
            out[p + "kda.q"] = (c.d_model, kd)
            out[p + "kda.k"] = (c.d_model, kd)
            out[p + "kda.v"] = (c.d_model, kd)
            out[p + "kda.b"] = (c.d_model, c.kda_heads)
            out[p + "kda.f1"] = (c.d_model, c.kda_dim)
            out[p + "kda.f2"] = (c.kda_dim, kd)
            out[p + "kda.g1"] = (c.d_model, c.kda_dim)
            out[p + "kda.g2"] = (c.kda_dim, kd)
            out[p + "kda.o"] = (kd, c.d_model)
        out[p + "moe.router"] = (c.d_model, c.n_experts)
        out[p + "moe.shared.g"] = (c.d_model, c.d_ff)
        out[p + "moe.shared.u"] = (c.d_model, c.d_ff)
        out[p + "moe.shared.d"] = (c.d_ff, c.d_model)
        for j in range(c.n_experts):
            out[p + f"moe.e{j}.g"] = (c.d_model, c.d_ff)
            out[p + f"moe.e{j}.u"] = (c.d_model, c.d_ff)
            out[p + f"moe.e{j}.d"] = (c.d_ff, c.d_model)
    out["head"] = (c.d_model, c.vocab)
    return out


def small_params(c: ModelConfig):
    """(name, kind) for int16 fixed-point parameters. kinds:
    n16 = Q2.13 1-centered norm offset; a16 = Q4.11 (conv kernels, dt_bias,
    residual-mix projections, router score-correction bias);
    u16 = Q8.8 unsigned (KDA A = exp(A_log))."""
    out = []
    for i, t in enumerate(c.layer_types):
        p = f"L{i}."
        out += [(p + "res_attn.norm.w", "n16"), (p + "res_attn.proj", "a16"),
                (p + "norm1.w", "n16")]
        if t == "F":
            out.append((p + "mla.knorm.w", "n16"))
        else:
            out += [(p + "kda.qconv", "a16"), (p + "kda.kconv", "a16"),
                    (p + "kda.vconv", "a16"),
                    (p + "kda.A", "u16"), (p + "kda.dtb", "a16"),
                    (p + "kda.onorm.w", "n16")]
        out += [(p + "res_mlp.norm.w", "n16"), (p + "res_mlp.proj", "a16"),
                (p + "norm2.w", "n16"), (p + "moe.bias", "a16")]
    out += [("res_out.norm.w", "n16"), ("res_out.proj", "a16"),
            ("final_norm.w", "n16")]
    return out


def small_param_shape(c: ModelConfig, name: str):
    kd = c.kda_heads * c.kda_dim
    if ".mla.knorm" in name:
        return (c.mla_dc,)
    if ".kda.onorm" in name:
        return (c.kda_dim,)
    if name.endswith((".norm1.w", ".norm2.w", ".norm.w")) \
            or name == "final_norm.w":
        return (c.d_model,)
    if name.endswith(".proj"):
        return (c.d_model,)
    if name.endswith(("conv",)):
        return (kd, c.conv_kernel)
    if name.endswith(".kda.A"):
        return (c.kda_heads,)
    if name.endswith(".kda.dtb"):
        return (kd,)
    if name.endswith(".moe.bias"):
        return (c.n_experts,)
    raise KeyError(name)
