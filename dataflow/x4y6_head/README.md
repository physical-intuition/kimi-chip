# X4Y6: embedding + final mix + final norm + LM head + argmax

Copy of X4Y5 (`dataflow/x4y5_norm_moe`) with the staged x0 replaced by the
official embedding table and the token path completed to 512 logits and a real
argmax, exactly as `reference/model.py` `RefModel.step`. Checked exactly
against the bit-exact integer model (`decoder_model.py`) and approximately
against the normative reference. See `CORRECTNESS.md` for what matches and
what does not, and `TASK.md` for the spec.

## What is new in RTL (dataflow_top.v)
- GLUE micro-program grows to 22 steps (`gl_pc` 0..21):
  - pc 0 `OP_EMB`: `x0[i] = (q - z) * s << 4` from the embedding ROM
    (`glue_weights/emb_{q,s,z}.hex`, int4 token-major, Q3.12 scales; the
    `<< 4` takes Q.12 x 2^-12 int4 units to Q16.16 exactly).
  - pc 19 `OP_MIX` sel 3: `out = res_mix([x0, x2], res_out)` (params in
    `small.hex` after the two layers' blocks).
  - pc 20 `OP_RMS`: `hn = RMSNorm(out, final_norm)`.
  - pc 21 `OP_HEAD`: per-vector exponent INT8 coding of `hn`, the untied
    64x512 int4 head on the shared INT4 MAC (one MAC per cycle, dequant folded
    into the dot product like every other projection), Q16.16 saturated logits,
    running strict-greater argmax (lowest index wins ties).
- `argmax_id` is the real argmax; the X4Y1 `token_id + 1` placeholder is gone.
- ~215.8k cycles/token (X4Y5 182.5k): the head adds 64x512 MACs.

## Verification
- `./run_decoder.sh` (needs numpy): ROM images reproduced from the official
  generator, then RTL runs A (6 tokens, 2 sequences), C (`GROUP_SIZE=64`
  build), B (public prompts as one 64-token sequence, refused 65th, restart)
  and D (the two public prompts, 48 + 16 tokens, each from `seq_start`).
  Every tensor through logits/argmax must equal `decoder_model.int_step`
  (`golden_decoder.py`); logits cosine vs `RefModel.step` is reported per
  row with argmax and MoE top-k flips. 20 single-value mutations must be
  rejected.
- `./run.sh` (strict): cycle-level golden.py on the RTL (argmax port checked
  against `decoder_model`), then the inference check: public prompts, logits
  cosine vs `RefModel` on the official weights, bar 0.98 on every row. Exits 2
  while that fails. `--diagnostic` skips the verdict.
- `python3 test_kda.py`, `test_mla.py`, `test_golden.py`,
  `test_reference.py`, `./tests/run.sh`: carried X4Y2-X4Y4 regressions.

Run inside the `x4env` container as the host user
(`docker run -u $(id -u):$(id -g) -e HOME=/tmp ...`), or with Icarus 12/13
plus python3 + numpy.
