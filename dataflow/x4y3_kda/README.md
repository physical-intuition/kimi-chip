# X4Y3: KDA (Kimi Delta Attention) operators

Copy of X4Y2 (`dataflow/x4y2_bounds`) with the KDA placeholder phases replaced by real arithmetic.

## What is implemented in RTL (dataflow_top.v)
- Projections q, k, v (64), f (64, Wf1 then Wf2), beta (2), z (64) on the existing unsigned INT4 MAC array. Signed values come from offset decomposition of accumulator deltas, so the MAC is unchanged.
- Causal depthwise conv, kernel 4, over q/k/v with a 3-token history (576 values), then SiLU.
- Per-head L2 norm of q and k (eps 1e-6), integer square root.
- Gates: beta = sigmoid, alpha = exp(-5 * sigmoid(A_h * (f + dt_bias))), via LUTs in kda_luts.vh.
- Delta rule per head on a 32x32 state: S = diag(alpha) S; u = v - kS; S += outer(beta k, u); out = qS / sqrt(dh).
- Gated RMSNorm (sigmoid gate, shared weight) and output projection.

Numbers are signed Q16.16, 32-bit saturating; products are floor(a*b / 2^16). Weights and embeddings are deterministic placeholders (see kda_model.py), not real Kimi weights.

## Verification
- `./run_kda.sh`: tb_kda.v runs 6 tokens across 2 sequences (with a restart) and dumps every KDA tensor, the conv history and the full state. golden_kda.py requires an exact match against kda_model.int_step and reports float64 error. A single corrupted state word must be rejected.
- `python3 test_kda.py`: 9 model tests (MAC decomposition, dimensions, conv history, L2 norm, gate ranges, LUT accuracy, delta-rule write property, fixed vs float).
- `./tests/run.sh`, tb_bounds, `./run.sh` and test_golden.py: the X4Y2 regressions, all passing.

Fixed-point vs float64 max abs error over the test sequence: q/k about 4e-5, attention about 4e-5, state about 3.5e-4, output about 1e-2.

## Not done
Real weights and quantization contract, feeding KDA output into the residual stream, layer norm/residual, MoE, and MLA softmax/value/output. This is not full inference. One side fix: MLA attention read mla_q out of range for dims >= 32 and produced X that poisoned the shared MAC accumulator; those dims are now zero.
