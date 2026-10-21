# X4Y1 golden-model harness

Status: implemented RTL diagnostic, NOT verified inference. No RTL changes.
Baseline: x3y5_timing at 36e1261. Existing untracked *_verified directories are
unrelated and are not used here.

Run `bash run.sh --diagnostic --report result.json` to check the real full-top
simulation against the Python arithmetic/storage reference. Run
`python3 -m unittest -v test_golden.py` for reference tests.
Without --diagnostic the runner intentionally exits 2 after producing its
report: missing operators and unknown data prohibit inference signoff.
Set RTL_DIR to another compatible implementation directory for later iterations.
The temporary trace is deleted; result.json is the compact reproducible report.
Set TRACE_PATH to retain a trace for replay with golden.py.

Three consecutive tokens exercise 0, 1 and 511, continuation and sequence restart,
two layers, full default dimensions and all attention cache positions. The
testbench streams pre-edge inputs and post-edge results. Python checks every
cycle of the unsigned INT4 MAC using a two-entry product queue, 16-product fold,
12-bit intermediate and 24-bit modular accumulation; pipeline staging; complete
projection and attention writebacks; synchronous banked SRAM read-before-write;
cache-count updates; and placeholder token completion. A mismatch fails with
the first cycle and field. Reference tests cover bubbles, overflow, unknowns
and mismatch rejection.

This is a datapath reference driven by the RTL's control/operand trace, not an
independent mathematical KDA/MLA inference implementation. It cannot catch
wrong operand selection or phase sequencing merely by matching arithmetic.
SRAM unknown words and arithmetic unknowns are tracked as None, not zero.
Unknown matching is diagnostic agreement, never numeric correctness. Zero operands mask unknown multiplicands in the partial-product RTL. Partial
unknown words are conservatively treated as entirely unknown; masks are not
bit-exact for individual X bits. Trace includes full projection result words,
not just debug hashes. KDA state is not checked because no state update exists.

Known blockers inherited from baseline:
* Convolution, KDA state/output, normalization, residual and MLA B/output
  have no mathematical implementation.
* argmax is token_id+1, not a logits reduction.
* Embedding low INT4 nibbles are zero, so normal projection tests are degenerate.
* MLA projection attempts 64 outputs into 32 slots. Upper writes are discarded.
* MLA attention indexes 128 query slots but only 32 exist and scans unwritten
  cache entries, introducing X values.
* Weights are destructively consumed and are not restored by reset. MAC
  accumulation is persistent across outputs/tokens.

Next iteration must define the actual missing operator/quantization/weight
contract, implement it, then add a transaction-level independent model with
nonzero operands and compare all layer tensors. Until then this harness is a
regression aid and a reproducible failure report, not a safe full-inference
optimization certificate. No PPA claims or physical-flow runs in this change.

Recorded validation: 1,180,736 checked cycles and 3 completed tokens;
192 writes each for KDA Q/K/V, MLA Q and attention scores; 96 SRAM writes.
160 MLA query write observations and 191 attention score observations are
unknown (including contamination after the first token). 392,190 attention
cycles contain unknown operands. All six inherited baseline regressions pass,
including exhaustive INT4 products and randomized MAC/reset tests.
Five Python reference tests pass. These counts describe diagnostics, not
successful numerical inference.
