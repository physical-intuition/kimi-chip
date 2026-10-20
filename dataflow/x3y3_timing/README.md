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
\n## Final routed results\n\nCompleted successfully in x3y3_timing_dataflow (exit 0). Clock remains 0.600 ns, I/O delays 0.100 ns. Source RTL a7a09b1.\n\nFinal setup WNS -0.282117 ns, TNS -18.0842 ns, 274 setup violations. Reported fmax 1.13364 GHz; this is a timing estimate, not timing closure at the target.\nWorst overall path is mla_kv_count[5] to debug_cache_hash[5]. Approximately 0.51 ns clock insertion plus clock-to-Q/XOR/output buffer yields 0.7821 ns arrival against 0.5000 ns required. Registering debug_q_hash exposed a different unregistered debug path.\nWorst register-to-register path is mac_b[3] to mac.prod_r[7], approximately -0.07 ns through the unsigned 4x4 multiplier and product-register mux.\nHold WNS +0.0849416 ns with zero hold violations. Zero max-capacitance, max-slew, and max-fanout violations. Minimum reported capacitance slack 1.62902 fF against its associated 10.4713 fF limit.\n\nInstance area excluding physical-only filler/tap cells is 408373 um^2: 339167 um^2 standard cells and 69205.8 um^2 across four macros. Core area 980179 um^2, die area 985076 um^2. The raw JSON repeats instance-area keys; the earlier 976748 value includes physical-only cells and must not be confused with the final functional-instance area.\nPower estimate 0.987002 W (internal 0.799977 W, switching 0.178010 W, leakage 0.0090152 W). This is vectorless/default-activity STA power, not measured inference power.\nDetailed router reports zero DRC errors and zero antenna violations. This is not independent signoff DRC/LVS.\n\nRaw final report, final metrics, route metrics and routing DRC report are archived in reports_final/. Full model/inference correctness remains unverified for the reasons in CORRECTNESS.md.\n