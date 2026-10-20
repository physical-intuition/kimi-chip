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

Full flow launched in x3y4_timing_dataflow. Routed results pending.
