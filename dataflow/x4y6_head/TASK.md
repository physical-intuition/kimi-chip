# X4Y6: Embedding lookup, final residual mix, final RMSNorm, LM head, argmax

## Base
Copy of X4Y5 (`dataflow/x4y5_norm_moe`). Keep:
- X4Y2 fixes (cache bounds, backpressure on a full cache until `seq_start`,
  valid-entry attention, no out-of-range reads).
- X4Y3 KDA, X4Y4 MLA and X4Y5 glue (RMSNorm, res_mix, MoE), bit-exact against
  their models.
- All X4Y2-X4Y5 regressions passing.

## Normative spec
`reference/model.py` (MoonshotAI/nano-kpu, vendored unmodified at
`third_party/nano-kpu`, commit e1855de, SHA-256 pinned), `RefModel.step`:

- `x0 = emb[token]`: token-major dequantized table (`dequant_emb`: per-row
  groups along d, scales int16 Q3.12, zeros uint8), vocab 512, d_model 64,
  official seeded synthetic tensors (seed 20260706).
- after the last layer: `x = res_mix(blocks + [x], "res_out")`; with block
  size 2 and 2 layers the candidates are `[x0, L1.out]`.
- `hn = rmsnorm(x, final_norm.w)`, `logits = hn @ head` (head is UNTIED,
  64 x 512 int4 standard layout).
- `forward_sequence` is teacher-forced; argmax over the 512 logits, ties to
  the lowest index. The argmax output is diagnostic; the next input token comes
  from the input stream.
- Pass bar (model.py docstring): logits cosine >= 0.98 on every row.

## Success criteria
1. RTL x0, final mix, final norm, head INT8 codes/exponent, all 512 logits and
   the argmax port exactly equal `decoder_model.int_step`, together with every
   X4Y5 tensor and the KV cache.
2. Logits cosine vs `RefModel.step` on multi-token sequences is the headline
   metric. Rows below 0.98, argmax flips and MoE top-2 flips are listed, never
   averaged away.
3. The strict gate (`./run.sh`) passes only if inference vs the normative
   reference meets the bar on every public-prompt row; otherwise it fails and
   lists why.
4. X4Y2-X4Y5 regressions pass.

## Not in scope
Official KDA weights in RTL (X4Y3 placeholders remain, see CORRECTNESS.md),
memory-image interface, msh_sram macros, runtime GROUP_SIZE (X5).
