# X4Y5: norm + residual mixing + MoE (both decoder layers wired)

Copy of X4Y4 (`dataflow/x4y4_mla`) with the NORM/RESIDUAL placeholder phases
replaced by a real GLUE phase that wires L0 (KDA) and L1 (MLA) exactly as
`reference/model.py` `RefModel.step` does, from x0 to L1.out. Checked exactly
against a bit-exact integer model (`decoder_model.py`) and approximately
against the normative reference (vendored unmodified at `third_party/nano-kpu`,
commit e1855de). See `CORRECTNESS.md` for what matches and what does not, and
`TASK.md` for the spec.

## What is implemented in RTL (dataflow_top.v)
- GLUE phase (24): a 19-step micro-program (`gl_pc`) of vector operators,
  one element or one MAC operand per cycle:
  - `x0` (STAGED placeholder embedding, see below)
  - L0: `h0 = RMSNorm(x0, L0.norm1)`, INT8 coding with a per-vector exponent,
    KDA, `a0 = KDA_out`, `m0 = res_mix([x0, a0], L0.res_mlp)`,
    `hb0 = RMSNorm(m0, L0.norm2)`, `x1 = a0 + MoE_0(hb0)`
  - L1 (second layer of attention-residual block 0):
    `m1 = res_mix([x0, x1], L1.res_attn)`, `h1 = RMSNorm(m1, L1.norm1)`, INT8
    coding, MLA, `pre = x1 + MLA_out`, `m2 = res_mix([x0, pre], L1.res_mlp)`,
    `h2 = RMSNorm(m2, L1.norm2)`, `x2 = pre + MoE_1(h2)` (= L1.out)
- RMSNorm: eps 1e-5, gain `1 + w` (Q2.13 offset), exact integer sqrt.
- res_mix: logits `rmsnorm(candidate, norm.w) @ proj`, softmax with the X4Y4
  exp LUT, output the p-weighted sum of the raw candidates.
- MoE: 64x8 router on the INT4 MAC, sigmoid LUT (X4Y3), bias affects top-2
  selection only (strict greater, lowest index wins ties), weights =
  selected raw sigmoid scores renormalized x 2.828, routed experts
  `(silu(h@g) * (h@u)) @ d` with d_ff 32, shared expert added unweighted.
  All expert/router weights are the official seeded int4 tensors
  (`glue_weights/moe_{q,s,z}.hex`, norm/mix/bias params `small.hex`).
- KDA input is now `RMSNorm(x0, norm1)` codes with a per-vector exponent, and
  the KDA o_proj input also uses a per-vector exponent (X4Y4 fixed e = 11,
  which clipped the real activations). The MLA placeholder `h_u` is gone; MLA
  consumes the real `h1`.

Staged, not faked: x0 is a deterministic placeholder embedding
(`decoder_model.emb_q`). The embedding table lookup, final `res_out` mixing,
final RMSNorm, LM head and argmax are X4Y6; argmax is still `token_id + 1`.

## Verification
- `./run_decoder.sh` (needs numpy; `PYTHON=...`): ROM images reproduced from
  the official generator, then RTL runs A (6 tokens, 2 sequences), C
  (`GROUP_SIZE=64` build + group-64 ROMs) and B (public prompts as one 64-token
  sequence filling the cache, a refused 65th token, restart, 2 more tokens).
  Every KDA tensor, MLA tensor, KV-cache SRAM word and glue value must equal
  `decoder_model.int_step` (`golden_decoder.py`), and L0.out / L1.out must be
  within cosine 0.99 of `RefModel.step` on the same x0 unless the token is a
  near-tie MoE top-2 flip (reported). 13 single-value mutations must be rejected.
- `python3 test_kda.py`, `test_mla.py`, `test_golden.py`, `test_reference.py`:
  operator model tests carried from X4Y3/X4Y4.
- `./tests/run.sh`, `./run.sh --diagnostic`: X4Y2-X4Y4 regressions on this
  RTL. `./run.sh` (strict) exits 2.
- The X4Y4 operator runners (`run_kda.sh`, `run_mla.sh`, `tb_kda.v`, `tb_mla.v`,
  `golden_kda.py`, `golden_mla.py`) are not carried: they assume the placeholder
  KDA/MLA inputs this RTL no longer has. Every tensor they compared is compared
  by `golden_decoder.py`, and they still run on the X4Y4 RTL in `x4y4_mla`.

Run inside the `x4env` container as the host user
(`docker run -u $(id -u):$(id -g) -e HOME=/tmp ...`), or with any Icarus 12/13
plus python3 + numpy.
