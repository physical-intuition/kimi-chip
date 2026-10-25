# X4Y4 correctness statement

Plain summary: the MLA operators of layer 1 are implemented in RTL with
real arithmetic. They match this directory's bit-exact integer model exactly
and track the normative float reference (`reference/model.py`) to cosine
>= 0.9992 on every output row tested. **This is still not inference.** The
MLA input is a staged placeholder, nothing feeds KDA output into MLA, and
norms, residual mixing, MoE, embedding and LM head are absent. The strict
gate (`./run.sh`) exits 2.

Weights: MLA uses the official seeded *synthetic* tensors from the reference
generator (`gen_weights`, public seed 20260706). KDA still uses the X4Y3
placeholder formulas. No trained weights exist for this task; the reference
itself is defined on synthetic weights.

## 1. Exact: RTL == bit-exact model (`mla_model.py`, `kda_model.py`)

| run | stimulus | compared | result |
|---|---|---|---|
| A | 6 tokens, 2 sequences (restart at token 5) | every MLA tensor (h codes, h@wc, latent norm, e_lat, lat codes, qc, qr, kr, kc, v, scores, softmax p, ctx, e_ctx, ctx codes, out) + all valid KV-cache SRAM words; every KDA tensor, conv history, state S | exact, no X/Z |
| B | public prompts 0+1 as one 64-token sequence (cache full), a 65th token offered without `seq_start` for 2000 cycles (refused), restart, 2 tokens | same, 66 tokens; softmax over all 64 entries; 4608 cache words at the end of the sequence | exact, no X/Z, refusal confirmed |
| C | `GROUP_SIZE=64` build + group-64 ROMs (2 groups on wk_c/wv), 5 tokens, 2 sequences | every MLA tensor + cache | exact |
| run_kda.sh | X4Y3 KDA regression (6 tokens) on this RTL | KDA tensors, history, S | exact |
| golden.py | 3 tokens, cycle-by-cycle | MAC accumulator/done, SRAM read-before-write and bank select, KV count, append writes only to entry `count`, reads only below `count*72`, SRAM idle elsewhere, every MLA matrix writes each output exactly once per token, no unknown MAC operands, placeholder argmax | match |

Mutation self-checks (run_mla.sh): one corrupted KV-cache word, softmax
probability, latent value or output value, and a wrong PROBE count, are each
rejected. run_kda.sh still rejects a corrupted state word.
Per-token run B numbers: `mla_result.json`.

## 2. Against the normative reference (float32 `reference/model.py`)

`nano_ref.py` builds a real `reference.model.RefModel` from the vendored,
SHA-256-pinned reference and calls `RefModel._mla(1, h)` on the same input.
Correctness for this chip is defined by cosine on logits (model.py header).
Per-operator numbers here are what can be measured before logits exist.

| quantity | A (6 tok) | B (66 tok, 64-entry cache) | C (group 64) |
|---|---|---|---|
| MLA out, min cosine | 0.99928 | 0.99965 (0.99994 at T = 64) | 0.99987 |
| MLA out, max abs err / max abs | 0.052 | 0.031 | - |
| latent norm, min cosine | > 0.99999 | > 0.99999 | > 0.99999 |
| softmax p, max abs err | 0.037 | 0.026 | - |

The dominant error is the INT8 coding of lat and ctx at the MAC input
(about 1/32 of the vector max per step). The exp LUT (< 1.5e-4) and the
latent RMSNorm (cos > 0.99999) contribute much less.

KDA against the reference (`test_reference.py`): the float64 KDA model now
equals `RefModel._kda` to < 1e-5 relative, so the structure is right. The
fixed-point KDA out cosine is 0.983 on a sequence's first token and 0.998 to
0.999 after that. The first-token weakness is the X4Y3 numerics (q.S is
tiny on token 0, so Q16.16 resolution is coarse before the gated norm).
It is recorded here and not fixed in X4Y4.

## 3. Chip-internal number formats (chosen, not taken from the reference)

docs/quantization.md makes internal formats the chip's choice, judged only
by the logit cosine. These are those choices, all modelled bit-exactly and
measured against model.py above. No reference behavior was invented:

- Q16.16 saturating int32 values; products floor(a*b / 2^16); 72-bit exact
  accumulators for sums of squares, q.k and p.v.
- MAC inputs as INT8 codes with value `(c-128)*2^(e-16)`. h uses e = 10. lat
  and ctx take the smallest e with max|x| >> e < 128, rounded half-up and
  saturated.
- Dequant exactly as `dequant_w4`, folded into the dot product:
  `sum_g s_g * sum_i (c_i-128)(q_i-z_g)`, then one floor shift.
- Softmax: max subtraction, exp(-d) from a 513-entry Q16 LUT over [0,16]
  (step 1/32, linear interpolation, generator in mla_model.py),
  `p = floor(e*2^16 / sum e)`. `1/sqrt(48)` is the constant 9459 in Q16.
- KV cache: expanded k/v (kc 64 + kr 16 + v 64 = 144 values per position,
  the same footprint as the latent + kr option in architecture.md), in
  Q16.16, 72 SRAM words per position.

## 4. Not implemented or not matching (explicit)

1. **MLA input is STAGED.** In the reference,
   `h = RMSNorm(res_mix(x, [emb], L1.res_attn), L1.norm1)` with
   `x = KDA_out + MoE_0(RMSNorm(res_mix(KDA_out, [emb], L0.res_mlp), L0.norm2))`
   (layer 1 is the second layer of attention-residual block 0). It needs
   RMSNorm, res_mix and MoE, which are X4Y5. Here h is a deterministic placeholder
   (`mla_model.h_u`, `mla_hu_f` in RTL). The KDA output (`kda_out`) is not
   connected to MLA, and `mla_out` (the residual input `a`) is computed but
   not consumed. NORM/RESIDUAL phases are still counters.
2. KDA input is the X4Y3 placeholder embedding, not `rmsnorm(emb[token], norm1)`.
   KDA weights are X4Y3 placeholder formulas (re-encodable as z = 8, s = 64).
3. No embedding, norm1/norm2/final norm, residual mixing, MoE or LM head.
   argmax is `token_id + 1`.
4. `GROUP_SIZE` is a compile-time parameter (128 default, 64 tested). The spec
   wants a single build that reads it from image header word 20.
5. Weights live in `$readmemh` ROMs, and state/activations in inferred reg
   arrays. The spec requires weights streamed over the 16 B/cycle memory port
   and all storage in `msh_sram` macros (`msh_chip_top` interface). That is X5.
6. Not timing-clean (wide combinational functions, ROM indexing). X1-X3
   physical numbers do not describe this design. About 141.4k cycles per
   token (KDA ~63.8k, MLA ~77.6k, almost all projection), + 86 per cached position.
7. Legacy weight shift registers and the X4Y2 pipe register remain, inert
   (`mac_pipe_v` stays 0), only so the X3 weight-shift equivalence regression
   still applies.

## 5. X4Y3 deviations found against model.py and fixed here

- KDA low-rank f/g width: reference `kda.f1/g1` are (d_model, kda_dim = 32)
  and `f2/g2` are (32, 64). X4Y3 used rank 8. Now 32.
- KDA gated RMSNorm eps: `rmsnorm` uses RMS_EPS = 1e-5. X4Y3 used the L2 eps
  1e-6 in both its RTL and its float model. With it, the X4Y3 float model
  differed from `RefModel._kda` by up to 155% of max |out| on the first
  token, a structural error that X4Y3's exact RTL==model check could not
  see. Now 1e-5.

X4Y3's directory and results are left untouched. These fixes exist only in
X4Y4's RTL and model.

## 6. Contract gaps

None blocked X4Y4. model.py defines the MLA math, the int4/scale/zero
layout (`dequant_w4`), the knorm encoding (Q2.13 offset, `1 + w`), eps,
and the score scale. Rounding and softmax numerics are chip choices under
the freedom rule (section 3).

Recorded for later: (a) model.py asserts `pos < max_seq` and defines nothing
past 64 positions. The chip refuses tokens until `seq_start`, consistent
with that. (b) The X4Y3 KDA placeholder weights have no reference
counterpart. The official KDA tensors arrive with the memory-image work.

## 7. Regressions and environment

- Frozen `dataflow/x4y2_bounds` and `dataflow/x4y3_kda` suites: all pass
  unchanged on Icarus 12.0 (ubuntu:24.04 container). Icarus 13 rejects their
  use-before-declaration, so they cannot build there.
- On this RTL (Icarus 12.0 and 13.0): `tests/run.sh` (protocol, MAC
  reference/pipeline, debug latency, weight-shift equivalence, X4Y4 bounds
  rewrite, 2048- and 4608-word banks), `run_kda.sh`, `test_golden.py`,
  `run.sh --diagnostic` exit 0. `run.sh` strict exits 2.
- Adapted, not just rerun: `tb_bounds.v` was rewritten for the real MLA
  (same intent, stronger checks). `golden.py`/`tb_golden.v` replace the
  legacy 32-output query/score writeback checks with per-matrix writeback
  coverage and SRAM bounds checks. `golden_kda.py` skips the MLA records.
  `run_kda.sh` links the 4608-word SRAM.
