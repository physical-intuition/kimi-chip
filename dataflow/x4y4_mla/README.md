# X4Y4: MLA (NoPE multi-head latent attention) operators

Copy of X4Y3 (`dataflow/x4y3_kda`) with the MLA skeleton replaced by real
arithmetic for layer 1, checked exactly against a bit-exact integer model and
approximately against the normative `reference/model.py` (vendored unmodified
at `third_party/nano-kpu`, commit e1855de). See `CORRECTNESS.md` for what
matches and what does not, and `TASK.md` for the spec.

## What is implemented in RTL (dataflow_top.v)
- Weights: official seeded synthetic MLA tensors from the reference generator
  (`gen_weights`, public seed 20260706) in the reference int4 format (packed
  nibbles, per (group, column) zero point and Q3.12 scale, group =
  min(GROUP_SIZE, fan_in)). ROM images: `mla_weights/*.hex` (`mla_model.py hex`).
- Projection engine extended with per-group zero-point dequantization on the
  unchanged unsigned INT4 MAC: latent compression `h @ wc` (128), queries
  `h @ wq_c` (2x32) and `h @ wq_r` (2x16), shared key `h @ wk_r` (16), latent
  decompression `lat @ wk_c` (2x32) and `lat @ wv` (2x32), output `ctx @ o`.
- Latent RMSNorm with knorm (eps 1e-5, gain 1 + w), per-vector INT8 coding of
  lat and ctx for the MAC.
- KV cache: kc, kr, v (144 Q16.16 values = 72 words) appended per position in
  a 9 x 512x64 SRAM (`kv_banked_4608x64.v`, 64 positions).
- Scores `[qc,qr] . [kc,kr] / sqrt(48)` streamed from SRAM over the valid
  entries only, softmax (max subtraction, 513-entry exp LUT `mla_luts.vh`,
  division), value weighted sum, output projection -> `mla_out`.
- X4Y2 rules kept: token refused when the cache is full until `seq_start`.
- KDA fixes found against model.py: f/z low rank 32 (X4Y3 had 8), gated
  RMSNorm eps 1e-5 (X4Y3 had 1e-6).

Staged, not faked: the MLA input `h` is a deterministic placeholder code
vector (`mla_model.h_u`); in the reference it is
`rmsnorm(res_mix(KDA_out + MoE_0, [emb]), norm1)`, which needs X4Y5 operators.

## Verification
- `./run_mla.sh` (needs numpy; `PYTHON=...`): model tests, reference tests,
  then RTL runs A (6 tokens, 2 sequences), B (public prompts as one
  64-token sequence filling the cache, a refused 65th token, restart, 2 more
  tokens) and C (group_size 64 build). Every MLA tensor and the KV-cache SRAM
  image must equal `mla_model.int_step`, KDA tensors must equal
  `kda_model.int_step`, and 5 single-value mutations must be rejected.
- `python3 test_mla.py`: 11 model tests (MAC zero-point identity, exact
  dequant floor, quantizer, exp LUT, softmax/causality, shared kr, capacity).
- `python3 test_reference.py`: vendored hashes, ROMs == generator output,
  MLA int vs `RefModel._mla` (64-entry cache, group 64), KDA vs `_kda`.
- `./run_kda.sh`, `./tests/run.sh`, `./run.sh --diagnostic`, `test_golden.py`:
  the X4Y3/X4Y2 regressions on this RTL. `./run.sh` (strict) exits 2.

Simulator: the RTL declares before use, so it builds on Icarus 12 and 13.
The frozen X4Y2/X4Y3 directories need Icarus <= 12 (13 rejects their
use-before-declaration).
