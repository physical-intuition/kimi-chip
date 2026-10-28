# X4Y5 correctness statement

Plain summary: both decoder layers are now wired as `reference/model.py`
`RefModel.step`, from x0 to L1.out, with RMSNorm, attention-residual mixing,
MoE and the residual adds in RTL. The RTL matches the bit-exact integer model
`decoder_model.py` exactly (every tensor, every token), and the model tracks
the float reference on L0.out and L1.out (cosine >= 0.9906 on every token
except one near-tie MoE flip, reported below). **This is still not
inference.** x0 is a staged placeholder embedding, and `res_out`, the final
norm, the LM head and argmax do not exist. The strict gate (`./run.sh`)
exits 2.

Weights: MLA, MoE (router, bias, 8 routed + shared experts), RMSNorm and
mixing parameters are the official seeded synthetic tensors from the reference
generator (`gen_weights`, public seed 20260706). KDA still uses the X4Y3
placeholder formulas (no reference counterpart; documented since X4Y3).

## 1. Exact: RTL == bit-exact model (`decoder_model.py`, run_decoder.sh)

| run | stimulus | compared | result |
|---|---|---|---|
| A | 6 tokens, 2 sequences (restart at token 5) | every KDA tensor, conv history, state S; every MLA tensor + valid KV-cache SRAM words; every glue value (x0, RMSNorm outputs, KDA/MLA input codes and exponents, res_mix logits/p/out, router logits, selection, weights, expert + shared outputs, x1, pre, x2) | exact, no X/Z |
| C | `GROUP_SIZE=64` build + group-64 ROMs, 5 tokens, 2 sequences | same | exact |
| B | public prompts 0+1 as one 64-token sequence (cache full), a 65th token refused for 2000 cycles, restart, 2 tokens | same, 66 tokens | exact, refusal confirmed |
| golden.py | 3 tokens, cycle by cycle | MAC, SRAM bounds/bank select, KV append/read bounds, per-matrix writeback, GLUE phase coverage | match |

13 single-value mutations (x0, a normed vector, MoE output, L1.out, an expert
selection, a routing weight, a router logit, a mix logit, a mix probability,
the KDA o_proj exponent, KDA out, MLA out, MLA input codes) are each rejected.
LUTs and ROM images are regenerated and compared before every run.

## 2. Against the normative reference (float32 `RefModel.step`)

`nano_ref.ref_decoder_trace` runs the real `RefModel.step` from the vendored,
SHA-256-pinned reference with the embedding table replaced by the same staged
x0 (the only substitution). It wraps `_moe` without changing it to record the
float selection keys `sigmoid(h @ router) + bias`.

| quantity | A (6 tok) | C (group 64) | B (66 tok, 64-entry cache) |
|---|---|---|---|
| L0.out min cosine | 0.99108 | 0.99917 | 0.99362 |
| L1.out min cosine | 0.99066 | 0.99492 | 0.99061 (excluding the flip) |
| MoE top-2 flips | 0 | 0 | 1 |

The flip: run B position 28 (token 339), layer 1. The reference picks experts
[4, 3], the integer router [4, 2]; the float keys of experts 2 and 3 differ by
6.4e-4 (0.56955 vs 0.57019). With a different second expert, L1.out cosine is
0.868. This is a top-k discontinuity, not an arithmetic bug: the RTL equals
the model exactly, and the model's keys put the pair the other way round
(0.57994 vs 0.5771). `golden_decoder.py` accepts a flip only when the swapped
experts' float keys are within 2e-3, prints every one, and excludes it from
the min cosine. Whether flips like this matter is a logit-level question for
X4Y6 (correctness for this chip is defined by cosine on logits).

The X4Y4 first-token KDA weakness (KDA out cosine 0.983) shrinks once the KDA
input is the real `RMSNorm(x0)` with a per-vector exponent: first-token
L0.out is >= 0.991. Not fully fixed; logits will decide whether more is needed.

## 3. Chip-internal number formats (chosen, not taken from the reference)

Carried from X4Y4: Q16.16 saturating activations, 72-bit accumulators, INT8
MAC codes `(c-128)*2^(e-16)`, reference int4 dequant folded into the dot
product, 513-entry exp LUT. New in X4Y5:

- RMSNorm: `r = isqrt(floor(sum x^2 / d) + round(1e-5 * 2^32))`,
  `y = mulq(sat32(trunc(x * 2^16 / r)), 65536 + 8w)` (Q2.13 gain offset).
- res_mix: Q16 logits `floor(sum rmsnorm(c)_i * proj_i / 2^11)` (proj Q4.11),
  softmax with the exp LUT, `p = floor(e * 2^16 / sum e)`, out = sat32 of the
  p-weighted raw-candidate sum.
- Every matmul input (KDA in, KDA o_proj in, MLA in, MoE in, expert act) is
  coded with the smallest exponent e such that max|x| >> e < 128. X4Y4
  hardwired e = 11 for the KDA o_proj input, which saturated real activations.
- MoE: sigmoid LUT (X4Y3), key = s + bias * 2^5, strict-greater top-2 scan
  (lowest index wins ties, as in the reference), `w = floor(s * RS / (s_a +
  s_b))` with RS = round(2.828 * 2^16), `act = mulq(mulq(g, sigmoid(g)), u)`.

## 4. Not implemented or not matching (explicit)

1. **x0 is STAGED**: `x0_i = (kda_model.x_u(t, i) - 128) * 2^7`, deterministic,
   with about the scale of the official embedding rows (std ~0.13). The
   embedding ROM lookup is X4Y6.
2. No final `res_out` mixing, final RMSNorm or LM head; argmax is
   `token_id + 1` (X4Y6).
3. KDA weights are the X4Y3 placeholders (z = 8, s = 2^-6).
4. `GROUP_SIZE` is a compile-time parameter (128 default, 64 tested); the spec
   wants it read from image header word 20 (X5).
5. Weights in `$readmemh` ROMs, activations in reg arrays; no `msh_chip_top`,
   memory port or `msh_sram` macros (X5).
6. Not timing-clean. About 182.5k cycles per token (X4Y4 ~141.4k; the GLUE
   phase adds ~41k, almost all MoE projections at one MAC per cycle), + 86 per
   cached position.

## 5. Contract gaps

None blocked X4Y5. model.py defines rmsnorm, res_mix, MoE routing (bias only
selects, renormalize, scale, unweighted shared expert, stable tie-break) and
the layer wiring. Rounding is a chip choice under the freedom rule. Recorded:
near-tie expert selection depends on numerics and the reference defines no
tolerance, so flips are reported per token rather than hidden.

## 6. Regressions and environment

- On this RTL (Icarus 12, `x4env` ubuntu:24.04 container): `run_decoder.sh`
  (A, C, mutations, B; ~17 min), `tests/run.sh` (protocol, MAC
  reference/pipeline, debug latency, weight-shift equivalence, bounds, 2048-
  and 4608-word banks), `test_kda.py`, `test_mla.py`, `test_golden.py`,
  `test_reference.py`, `run.sh --diagnostic` all exit 0. `run.sh` strict
  exits 2.
- X4Y4 suite rerun on its own RTL: PASS. Frozen X4Y2/X4Y3/X4Y4 directories
  are untouched.
- Not carried: X4Y4's `run_kda.sh`/`run_mla.sh` and their testbenches/golden
  scripts assume the placeholder KDA/MLA inputs this RTL no longer has.
  Everything they compared is compared by `golden_decoder.py`.
