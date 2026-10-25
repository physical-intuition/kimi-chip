"""Deterministic synthesis of nano tensors from a global seed.

Weight format (AWQ/GPTQ-inspired, hardware-oriented):
  * standard matmul weights: int4 packed 2/byte along fan_in
    (`<t>.q` uint8 [fan_in/2, fan_out]), per-(group, out-channel)
    asymmetric params with group = min(group_size, fan_in):
    scales `<t>.s` int16 Q3.12, zero points `<t>.z` uint8 (0..15);
    w = (q - z) * s * 2^-12  (see reference/model.py::dequant_w4).
  * embedding `emb`: token-major, packed along d_model per token row,
    per-row groups (dequant_emb). The LM head `head` is untied and uses
    the standard layout.
  * small params: int16 fixed point (norm offsets Q2.13, conv/dt_bias/
    residual-mix projections/router bias Q4.11, KDA A=exp(A_log)
    unsigned Q8.8).

Scales follow a variance-preserving recipe (~1/(sigma_q * sqrt(fan_in)))
computed with pure-integer arithmetic so generation is bit-reproducible.

Byte accounting (MoE makes the two notions differ — see harness/evaluate.py):
  * active_weight_bytes: quantized bytes an ideal no-cache design streams
    PER TOKEN — all dense tensors + top_k routed experts + one embedding
    row. This is the numerator of the bandwidth roofline.
  * floor_weight_bytes: bytes every clean run MUST read at least once —
    the dense tensors only (which experts run is data-dependent, and
    embedding rows depend on the tokens, so both are excluded; the floor
    is deliberately conservative).
"""

import math

import numpy as np

from .config import ModelConfig
from .model import matmul_shapes, small_params, small_param_shape
from .prng import rand_int_range

SIGMA_Q_X1000 = 4610      # std of uniform{0..15} = sqrt(255/12) = 4.610

# per-destination gain trim in 2^(x/4) units (negative = smaller outputs).
# b (KDA beta) and f2 (KDA decay input) feed sigmoid gates and want modest
# pre-activations.
FUDGE_Q2 = {"b": -6, "f2": -6}


def _scale_q12(fan_in: int, kind: str) -> int:
    """int16 Q3.12 scale ~ 2^(fudge/4) / (4.61 * sqrt(fan_in))."""
    s = (4096 * 1000 * 1024) // (SIGMA_Q_X1000 * math.isqrt(fan_in * 1024 * 1024))
    f = FUDGE_Q2.get(kind, 0)
    s = int(s * (2.0 ** (f / 4.0))) if f else s
    return max(1, min(32767, s))


def _kind_of(name: str) -> str:
    return name.split(".")[-1]


def tensor_list(c: ModelConfig):
    """Canonical (name, shape, tag) list. The memory-image descriptor table
    indexes tensors in exactly this order (docs/memory_map.md). Tags:
    q4 = packed int4, s16 = scales, z8 = zeros, p16 = int16 small param."""
    g = c.group_size
    shapes = matmul_shapes(c)

    def triple(nm):
        k, n = shapes[nm]
        grp = min(g, k)
        return [(nm + ".q", (k // 2, n), "q4"),
                (nm + ".s", ((k + grp - 1) // grp, n), "s16"),
                (nm + ".z", ((k + grp - 1) // grp, n), "z8")]

    def p16(nm):
        return (nm, small_param_shape(c, nm), "p16")

    out = []
    ng_e = (c.d_model + min(g, c.d_model) - 1) // min(g, c.d_model)
    out += [("emb.q", (c.vocab, c.d_model // 2), "q4"),
            ("emb.s", (c.vocab, ng_e), "s16"),
            ("emb.z", (c.vocab, ng_e), "z8")]
    for i, t in enumerate(c.layer_types):
        p = f"L{i}."
        out += [p16(p + "res_attn.norm.w"), p16(p + "res_attn.proj"),
                p16(p + "norm1.w")]
        if t == "F":
            for nm in ["wc", "wq_c", "wq_r", "wk_c", "wk_r", "wv", "o"]:
                out += triple(p + "mla." + nm)
            out.append(p16(p + "mla.knorm.w"))
        else:
            for nm in ["q", "k", "v", "b", "f1", "f2", "g1", "g2", "o"]:
                out += triple(p + "kda." + nm)
            for nm in ["qconv", "kconv", "vconv", "A", "dtb", "onorm.w"]:
                out.append(p16(p + "kda." + nm))
        out += [p16(p + "res_mlp.norm.w"), p16(p + "res_mlp.proj"),
                p16(p + "norm2.w")]
        out += triple(p + "moe.router")
        out.append(p16(p + "moe.bias"))
        for nm in ["g", "u", "d"]:
            out += triple(p + "moe.shared." + nm)
        for j in range(c.n_experts):
            for nm in ["g", "u", "d"]:
                out += triple(p + f"moe.e{j}." + nm)
    out += [p16("res_out.norm.w"), p16("res_out.proj"), p16("final_norm.w")]
    out += triple("head")
    return out


def gen_weights(c: ModelConfig, seed: int) -> dict:
    """name -> numpy array, matching tensor_list."""
    w = {}
    shapes = matmul_shapes(c)
    for name, shape, tag in tensor_list(c):
        n = int(np.prod(shape))
        stream = f"{c.name}/{name}"
        if tag == "q4":
            lo = rand_int_range(seed, stream + "/lo", n, 0, 15)
            hi = rand_int_range(seed, stream + "/hi", n, 0, 15)
            w[name] = ((hi << 4) | lo).astype(np.int64).reshape(shape)
        elif tag == "z8":
            w[name] = rand_int_range(seed, stream, n, 6, 9).reshape(shape)
        elif tag == "s16":
            base = name[:-2]
            fan_in = c.d_model if base == "emb" else shapes[base][0]
            s0 = _scale_q12(fan_in, _kind_of(base))
            # +-25% per-entry jitter around the variance-preserving scale
            j = rand_int_range(seed, stream, n, -s0 // 4, s0 // 4)
            w[name] = np.maximum(1, s0 + j).reshape(shape)
        elif tag == "p16":
            if name.endswith(".kda.A"):
                w[name] = rand_int_range(seed, stream, n, 128, 1024).reshape(shape)
            elif name.endswith("conv"):
                w[name] = rand_int_range(seed, stream, n, -1024, 1023).reshape(shape)
            elif name.endswith((".proj", ".moe.bias")):
                w[name] = rand_int_range(seed, stream, n, -512, 511).reshape(shape)
            elif name.endswith(".kda.dtb"):
                w[name] = rand_int_range(seed, stream, n, -2048, 2047).reshape(shape)
            else:                          # 1-centered norm offsets, Q2.13
                w[name] = rand_int_range(seed, stream, n, -2048, 2047).reshape(shape)
    return w


def gen_tokens(c: ModelConfig, seed: int, prompt_idx: int) -> np.ndarray:
    """Teacher-forced token sequence; length = seq_lens[prompt_idx]."""
    n = c.seq_lens[prompt_idx]
    return rand_int_range(seed, f"{c.name}/tokens/{prompt_idx}", n,
                          0, c.vocab - 1)


def _entry_bytes(shape, tag) -> int:
    n = int(np.prod(shape))
    return n if tag in ("q4", "z8") else 2 * n


def active_weight_bytes(c: ModelConfig) -> int:
    """Quantized bytes streamed per token by an ideal no-cache design:
    all dense tensors, plus top_k routed experts per layer (all experts
    are the same size), plus one embedding row. Numerator of the
    bandwidth roofline."""
    g = min(c.group_size, c.d_model)
    ng_e = (c.d_model + g - 1) // g
    emb_row = c.d_model // 2 + ng_e * 3          # q4 row + s16 + z8 per row
    dense = 0
    expert0 = 0                                  # one expert's triple bytes
    for name, shape, tag in tensor_list(c):
        if name.startswith("emb."):
            continue
        if ".moe.e" in name:
            if name.startswith("L0.moe.e0."):
                expert0 += _entry_bytes(shape, tag)
            continue
        dense += _entry_bytes(shape, tag)
    return dense + c.n_layers * c.top_k * expert0 + emb_row


def floor_weight_bytes(c: ModelConfig) -> int:
    """Bytes every clean run must read at least once: the dense tensors
    (everything except the data-dependent routed experts and embedding
    rows). Conservative lower bound — see harness/evaluate.py."""
    return sum(_entry_bytes(shape, tag) for name, shape, tag in tensor_list(c)
               if not name.startswith("emb.") and ".moe.e" not in name)
