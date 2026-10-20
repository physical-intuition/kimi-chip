# X3Y3 timing iteration

This is a new large-dimension timing experiment. Historical x3y3 and x3y3_large are untouched.

Baseline X3Y2 large routed at 0.6 ns with 0.1 ns input/output delays.
Worst overall path: KDA Q register to combinational debug_q_hash, approximately -0.275 ns.
Worst register-to-register path: mac_pipe_v through decode and a deep buffer tree to a weight shift-register enable, approximately -0.09 ns.
One routed maximum-capacitance violation was reported (123.29 fF versus 121.15 fF).

Changes:
- Register debug_q_hash, adding one cycle of debug-only latency.
- Pipeline and distribute the weight shift enables in 256-bit segments.
  A head-nibble bypass preserves logical weight stream timing, including consecutive shifts.
  Full randomized logical-state/head equivalence is tested against the pre-timing RTL.
- Use ABC speed mapping rather than area mapping.
- Request 10 percent capacitance and slew margin during repair.
- Keep the original 0.6 ns clock and 0.1 ns I/O delays. No new false paths.

Based on the existing x3y3_large protocol/MAC-corrected baseline.
Unsigned INT4 MAC and protocol completion tests pass. This does not establish
model/inference correctness; inherited placeholder weights, unsupported MLA
indices and other blockers in CORRECTNESS.md remain.

Run tests with bash tests/run.sh from this directory.
Physical flow runs in container x3y3_timing_dataflow with the ORFS image and
this directory mounted as designs/nangate45/dataflow_top.
Final metrics will be saved after routing completes.
