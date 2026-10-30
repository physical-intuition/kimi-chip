# X4Y6 correctness statement

Plain summary: the token path is complete in RTL. Official embedding row in,
both decoder layers, final res_out mix, final RMSNorm, untied LM head to 512
logits, real argmax out. The RTL matches the bit-exact integer model
(`decoder_model.py`) exactly on every tensor, every logit and the argmax.
**Inference is NOT verified against the normative reference, and the strict
gate (`./run.sh`) exits 2.** The main reason: L0's KDA weights are still the
X4Y3 placeholders, so against `reference/model.py` with the official weights
the logits are essentially uncorrelated (min cosine -0.35, argmax agreement
3/64). With those placeholders substituted into the reference, logits cosine is
0.991 mean but 4/64 public-prompt rows fall below the 0.98 bar, all from MoE
expert-selection differences.

## 1. Exact: RTL == bit-exact model (`run_decoder.sh`)

| run | stimulus | result |
|---|---|---|
| A | 6 tokens, 2 sequences | exact |
| C | `GROUP_SIZE=64` build + group-64 ROMs, 5 tokens, 2 sequences | exact |
| B | public prompts as one 64-token sequence (cache full), refused 65th, restart, 2 tokens | exact, refusal + restart confirmed |
| D | public prompts 0 (48 tok) and 1 (16 tok), each from `seq_start` | exact |

Compared: x0 (embedding lookup), every KDA/MLA tensor and KV-cache SRAM word,
every X4Y5 glue value, the res_out mix (logits, p, out), final RMSNorm output,
head INT8 codes and exponent, all 512 logits, argmax. 20 single-value
mutations (incl. x0, final mix out, head codes/exponent, one logit, argmax)
are each rejected. `golden.py` (strict/diagnostic run.sh) also checks the
`argmax_id` port against `decoder_model` cycle by cycle.

## 2. Against the normative reference (logits cosine, the headline metric)

`nano_ref.ref_decoder_trace` runs `RefModel.step` from the vendored,
SHA-256-pinned `model.py`. Two references:

**(a) fully official weights (normative, used by the strict gate)**, public
prompts teacher-forced, 64 rows: min cosine -0.350, mean 0.187, 64/64 rows
below 0.98, argmax agreement 3/64. Fails the bar.

**(b) same reference with the X4Y3 KDA placeholders substituted** (what the RTL
implements; isolates the fixed-point error of everything else):

| run | logits min cos | mean | rows < 0.98 | argmax flips | MoE top-2 flips |
|---|---|---|---|---|---|
| A (6 tok) | 0.9985 | 0.9990 | 0 | 0 | 0 |
| C (group 64, 5 tok) | 0.7995 | 0.9582 | 1 (row 3) | 1 (ref 338, chip 489, ref top-2 gap 0.110) | 1 (L1, key gap 0.039) |
| B (64-tok cache) | 0.6771 | 0.9914 | 4 (rows 0, 18, 28, 29) | 6 (rows 6, 7, 14, 18, 54, 60) | 4 (L1, key gaps 0.0030, 0.0111, 0.0133, 0.0003) |
| D (public prompts, 64 rows) | 0.6771 | 0.9912 | 4 (P0 pos 0, 18, 28, 29) | 6 (P0 pos 6, 7, 14, 18; P1 pos 5, 7) | 4 (same as B) |

Public prompts, group 128 (run D, RTL): min
0.677, mean 0.991, rows below 0.98 = prompt 0 positions 0, 18, 28, 29
(cos 0.933, 0.933, 0.677, 0.950). Every one is an L1 MoE second-expert
difference; float key gaps 0.0030, 0.0111, 0.0133, 0.0003. Argmax flips:
prompt 0 positions 6, 7, 14, 18 (reference top-1/top-2 logit gaps 0.024,
0.016, 0.010, 0.005), prompt 1 positions 5, 7 (0.014, 0.004).

### Router near-ties (the X4Y5 question)
The X4Y5 token-339 flip (key gap 6.4e-4) does reach the logits: it is
prompt 0 position 28, logits cosine 0.677. But near-ties are not the whole
story: integer router keys differ from the float ones by up to ~0.03, from
error accumulated upstream in h2 (KDA/MLA INT8 coding), so gaps of 0.01-0.04
flip too (group 64 run C: 0.039). Computing the router in full precision on the
integer h2 did not fix it (made prompt 1 position 9 worse), so the fix is
upstream precision, not the router. Group 64 is worse than 128 on the public
prompts (model-only: min 0.699, 8 argmax flips; prompt 1 min 0.953).

## 3. Chip-internal number formats (new in X4Y6)
- Embedding: `x0[i] = (q - z) * s << 4` exactly (int4 q, uint8 z, Q3.12 s,
  per-row groups along d; Q.12 x 2^-12 in Q16.16 is a left shift by 4).
- res_out mix: same operator as X4Y5 res_mix, candidates [x0, L1.out].
- Final RMSNorm: X4Y5 RMSNorm (eps 1e-5, Q2.13 gain offset).
- Head: `hn` coded to INT8 with a per-vector exponent (X4Y5 choose_e rule),
  64x512 int4 head, group dequant folded into the dot product, logits Q16.16
  saturated int32. Argmax strict greater over the 512 logits, lowest index on
  ties (matches `np.argmax`).

## 4. What still blocks inference signoff
1. **KDA weights are X4Y3 placeholders** (fixed z = 8, s = 2^-6). This alone
   makes reference (a) fail. Next step: official L0.kda tensors in the KDA ROM
   path (the reference int4 format MLA/MoE already use).
2. **Precision**: even with matched weights, 4/64 rows miss 0.98 through MoE
   selection flips driven by upstream INT8 coding error (~0.03 key error).
3. Weights are official seeded synthetic tensors in on-chip ROM, not streamed
   from the memory image; no chip interface (msh_chip_top, memory port, image
   header, msh_sram macros); `GROUP_SIZE` is compile-time. (X5.)
4. Not timing-clean: wide combinational helpers; ~215.8k cycles/token.

## 5. Regressions and environment
Icarus 12, `x4env` (ubuntu 24.04). In this dir: `run_decoder.sh` (A, C, B,
D, mutations), `test_kda.py`, `test_mla.py`, `test_golden.py`,
`test_reference.py`, `tests/run.sh`, `run.sh --diagnostic`: all exit 0;
`run.sh` strict exits 2. Frozen X4Y2-X4Y5 dirs rerun on their own RTL:
x4y2_bounds, x4y3_kda (incl. run_kda.sh), x4y4_mla (incl. run_kda.sh, run_mla.sh),
x4y5_norm_moe (incl. run_decoder.sh A/C/B, unchanged numbers): all pass, each
strict run.sh exits 2.
