# X4Y5: Implement RMSNorm, attention-residual mixing and MoE; wire both layers

## Base
Copy of X4Y4 (`dataflow/x4y4_mla`). Keep:
- X4Y2 fixes (cache bounds, backpressure on a full cache until `seq_start`,
  valid-entry attention, no out-of-range reads).
- X4Y3 KDA and X4Y4 MLA operators, bit-exact against their models.
- All X4Y2-X4Y4 regressions passing; the strict inference gate (`./run.sh`
  without `--diagnostic`) must keep failing while inference is incomplete.

## Normative spec
`reference/model.py` (MoonshotAI/nano-kpu, vendored unmodified at
`third_party/nano-kpu`, commit e1855de): `RefModel.step`, `_res_mix`, `_moe`,
`rmsnorm`, `l2norm`. nano: d_model 64, 2 layers (L0 KDA, L1 MLA), attention-
residual block size 2, 8 routed experts top-2 + 1 shared, d_ff 32, RMSNorm eps
1e-5, L2 eps 1e-6, router scale 2.828, int4 group 128.

- `rmsnorm(x, w) = x / sqrt(mean(x^2) + 1e-5) * (1 + w)`
- `res_mix(cands, P)`: `logit_c = rmsnorm(c, P.norm) . P.proj`,
  `p = softmax(logits)`, `out = sum_c p_c * c` (raw candidates)
- `moe(h)`: `s = sigmoid(h @ router)`; top-2 of `s + bias` (bias only selects,
  lowest index wins ties); `w = s_sel / sum(s_sel) * 2.828`;
  `out = shared(h) + sum_j w_j * expert_j(h)`,
  `expert(h) = (silu(h @ g) * (h @ u)) @ d`
- Layer wiring (block 0 = [emb]):
  - L0: `a0 = KDA(rmsnorm(x0, L0.norm1))`,
    `x1 = a0 + MoE_0(rmsnorm(res_mix([x0, a0], L0.res_mlp), L0.norm2))`
  - L1: `h = rmsnorm(res_mix([x0, x1], L1.res_attn), L1.norm1)`,
    `pre = x1 + MLA(h)`,
    `x2 = pre + MoE_1(rmsnorm(res_mix([x0, pre], L1.res_mlp), L1.norm2))`

## Success criteria
1. RTL glue values (x0, every RMSNorm, res_mix logits/p/out, router logits,
   selection, weights, expert outputs, residual adds) and all KDA/MLA tensors
   and the KV cache exactly equal `decoder_model.int_step`.
2. `decoder_model` tracks `RefModel.step` (float) on L0.out and L1.out with the
   official seeded synthetic weights, including a full 64-entry cache. MoE
   top-2 flips caused by near ties are reported, not hidden.
3. Cache bounds/refusal/restart unchanged.
4. X4Y2-X4Y4 regressions pass; strict gate still fails.

## Staged (not faked)
x0 is a deterministic placeholder embedding (`decoder_model.emb_q`): the
embedding table ROM is X4Y6, together with final `res_out` mixing, final
RMSNorm, LM head and argmax.

## Not in scope
Embedding lookup, final norm, LM head/argmax (X4Y6); memory-image interface,
msh_sram macros, runtime GROUP_SIZE (X5).
