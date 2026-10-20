# X3Y4 timing iteration

New experiment based on x3y3_timing. Historical experiments and unrelated
uncommitted work are untouched.

## Measured baseline

The actual x3y3_timing_dataflow final report gives -0.282117 ns setup slack,
1.13364 GHz reported fmax, 274 setup-violating endpoints, and 408373 square
micrometers of placed instance area (339167 standard cells + 69205.8 macros).
The kickoff numbers (0.908 GHz / 88k area) describe a different result and must
not be used as this variant's baseline. See baseline_reports for source data.

Worst overall path is mla_kv_count to combinational debug_cache_hash.
Clock insertion is about 0.51 ns versus a 0.50 ns output requirement.
Worst register-to-register path is mac_b through the 4x4 multiplier to
mac.prod_r, about -0.07 ns. No baseline hold, capacitance or slew violations.

## Changes

All three debug hashes are registered together, sampled one cycle behind
internal state. Q hash was already registered; state/cache gain a debug cycle.
This removes debug XOR logic from register-to-output paths, but does not by
itself solve excessive clock insertion delay.

MAC now has three stages: two independent two-bit partial products, product
reduction, and accumulation. Initiation interval remains one cycle; done and
results are one cycle later. The existing controller waits on done, and the
protocol regression completes one cycle later than baseline.

CTS uses BUF_X8 / BUF_X16 and clusters of at most 32 sinks to investigate
lower insertion latency with this large clock load. Actual routed timing is
required to establish whether this helps.

Clock target remains 0.6 ns, I/O delays remain 0.1 ns, and false paths are
unchanged. No constraint relaxation.

## Verification

Run bash tests/run.sh. All pass:
- Completion pulse at 393580 cycles.
- Unsigned INT4 MAC directed test.
- Exhaustive 256 operand pairs and 20000 random cycles, bubbles, reset aborts,
  checking exact three-stage latency and 941 fold results.
- 100 randomized registered debug hash samples and reset.
- 12000 random logical weight-state/head equivalence cycles.
- All 2048 banked SRAM addresses, bank boundaries and CE hold.

These tests do not establish full inference correctness. Inherited blockers
remain documented in CORRECTNESS.md.

## Physical results

Full routed flow completed successfully (container exit 0). The unchanged
0.6 ns target does NOT close: worst setup slack is -0.0245119 ns, TNS
-0.408776 ns, and 39 setup-violating endpoints. Reported fmax is
1.60125 GHz, up 41.25% from the actual X3Y3 baseline of 1.13364 GHz.
Setup slack improves from -0.282117 ns; violating endpoints fall from 274.

Worst overall path is debug_q_hash[26] register to its output port:
0.5245 ns arrival versus 0.5000 ns required, with about 0.3286 ns clock
insertion. Worst register-to-register path is mac.prod_r[1] to mac.acc[21],
with +0.01 ns setup slack (rounded report precision). The pipelined MAC
register-to-register path now meets; constrained debug outputs remain limiting.

Hold worst slack is +0.0282831 ns, with zero hold violations. There are
zero slew/fanout violations, but two max-capacitance violations at
place7308/Z and place7307/Z (2.36 fF and 1.45 fF over the limit).
Final detailed routing reports zero geometric DRC violations; the final
5_route_drc reports are empty, confirmed by the routing log's final zero count.
This is route DRC, not a claim of independent foundry signoff.

Placed instance area excluding filler is 407285 square micrometers
(338079 standard cells + 69205.8 macros), down 0.27% from 408373.
The metrics JSON contains a duplicate instance-area key: the earlier 977124
includes filler and must not be compared against the baseline non-filler area.
Vectorless estimated power is 1.05279 W, up 6.67% from 0.987002 W;
this is not measured silicon power.

Final reports are in reports_final/ and metrics_final.json.
Full inference remains unverified because of the inherited CORRECTNESS.md
blockers. No clock/I/O/false-path constraint relaxation was used.
