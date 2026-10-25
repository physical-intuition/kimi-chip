# X4Y4: Implement MLA (NoPE multi-head latent attention) operators

## Base
Copy of X4Y3 (`dataflow/x4y3_kda`). Keep:
- X4Y2 fixes: cache bounds checking, backpressure on a full cache until an
  explicit sequence restart, attention over valid entries only, no
  out-of-range reads.
- X4Y3 KDA operators, bit-exact against `kda_model.py`.
- All X4Y2 and X4Y3 regressions passing; the strict inference gate (`./run.sh`
  without `--diagnostic`) must keep failing while inference is incomplete.

Note: `dataflow/x4y4/`, `x4y4_reports/`, `x4y5*/`, `x5y*/` are physical-flow
runs from before the X/Y scheme was fixed (old numbering, timing only). They
are unrelated to harness X4 and are not renumbered.

## Normative spec
`reference/model.py::RefModel._mla` (MoonshotAI/nano-kpu, vendored unmodified
at `third_party/nano-kpu`, commit e1855de) plus docs/architecture.md. nano:
H = 2, dk = 32, dr = 16 (shared), dv = 32, dc = 128, d_model = 64,
max_seq = 64, int4 group 128, RMSNorm eps 1e-5.

1. Latent: `lat = RMSNorm(h @ wc, knorm)` (dc = 128, gain `1 + w`, Q2.13).
2. Queries: `qc = h @ wq_c` [H, dk], `qr = h @ wq_r` [H, dr].
3. Keys/values: `kc = lat @ wk_c` [H, dk], `kr = h @ wk_r` [dr] shared by
   all heads, `v = lat @ wv` [H, dv]. NoPE: nothing is rotated.
4. Per head: `p = softmax([qc_h, qr_h] . [kc_h, kr]_t / sqrt(dk + dr))` over
   every cached position t, including the current token; `ctx_h = p @ V_h`.
5. `out = concat(ctx) @ o`.
6. Weights: int4 `w = (q - z) * s * 2^-12`, z/s per (group, column),
   group = min(group_size, fan_in), packed two per byte along fan_in.

## Architecture position
`L1 = MLA`, attention-residual block size 2, so L1 is the second layer of
block 0: `h = RMSNorm(res_mix(x, [emb], L1.res_attn), L1.norm1)` where
`x = KDA_out + MoE_0(...)` from layer 0. That needs RMSNorm, res_mix and MoE,
which are X4Y5. **Staged**: the MLA input is a deterministic placeholder
code vector (`mla_model.h_u`), clearly marked in RTL and docs; the MLA
output `mla_out` is the residual input `a` but is not added anywhere yet.

## Success criteria
1. MLA RTL tensors (latent, norm, q/k/v, scores, softmax, ctx, output) and
   the KV-cache SRAM image exactly equal `mla_model.int_step`.
2. `mla_model` tracks `reference/model.py` (float) closely on the official
   synthetic weights, including a full 64-entry cache.
3. Cache bounds: writes only to the appended entry, reads only from valid
   entries, refusal of a 65th token, restart.
4. KDA still exact; X4Y2/X4Y3 regressions pass; strict gate still fails.

## Not in scope (X4Y5+)
RMSNorm norm1/norm2/final, residual mixing, MoE, embedding, LM head/argmax,
memory-image interface (X5 harness work).
