# X4Y2 bounded MLA traversal, not full inference
Parent 077c37d, RTL copied from x3y5_timing. This directory is an isolated
successor; no historical or unrelated untracked iteration is modified.

Fixed the provable control bugs without inventing missing model mathematics.
MLA projection now emits MLA_HEADS*MLA_DK outputs rather than KDA_HEADS*KDA_DIM.
Attention scans only valid cache entries. A full MAX_SEQ sequence applies
input backpressure until seq_start, rather than wrapping the SRAM address.
The prototype remains limited to its default dimensions.

Remaining blockers prohibit full inference signoff:
- A 32-element query is used by a 128-dimensional attention loop. There is no
  supplied query up-projection matrix or explicit contraction contract.
- Convolution, KDA recurrence gates/state/output, MLA latent KV projection,
  value weighting/softmax, output projections, norm and residual are absent.
- Argmax is token_id+1, and embeddings/weights are synthetic placeholders.
- MAC fold accumulator persists between outputs; weights are consumed.
- INT4 signedness, activation format, rounding, saturation and scaling have
  no complete numerical contract. Existing MAC explicitly uses unsigned INT4.
- SRAM operand prefetch/staging is not an independent correct attention path.

Do NOT clamp the query index, fill X values with zeros, or redefine inference
as a smaller dot product in order to obtain a passing result.
Need an executable reference with actual weights and precise intermediate
tensor/quantization contracts before X4Y3-X5Y5 can constitute verified
inference optimizations. experiments/KIMI_SPEC.md gives only a recurrence and
high-level dimensions, not the missing contract. audit/harness/verify_golden.py
is an unimplemented stub whose empty outputs can spuriously compare equal;
it is not used for signoff here.

Validation:
- All six inherited regression suites pass.
- Directed query-write bounds, valid-cache traversal, full-cache backpressure
  and sequence restart test passes.
- Five Python golden reference tests pass.
- Full-top diagnostic matches 697408 cycles / 3 tokens, 96 MLA query writes,
  96 SRAM writes and 4 valid-entry scores (contexts 1, 2, 1).
- Unknown attention operands remain (6653 cycles); 2/4 scores unknown.
- Strict verification must continue to exit 2.
No PPA claim, no full inference claim.
