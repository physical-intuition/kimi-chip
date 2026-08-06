# v9 / v10: findings on v4, fixes, and two speedups

Follow-up to the v2–v8 sprint. Everything here is additive (v4 untouched);
all claims reproduce with the testbenches in `tb/` and the standard ORFS
nangate45 flow, frozen 26Q2 image.

## Two findings on v4 (worth knowing regardless of v9/v10)

**1. v4 double-accumulates.** `mac_en` stays asserted across FETCH and the
following COMPUTE while both the address and the SRAM read are registered, so
every element except the last is added twice. Repro: `tb/tb_v4_count.v` —
all-ones inputs, K=4, correct sum 4, v4 returns **7** (elements 0–2 twice +
element 3 once). The core computes `2·Σ − last`, not the dot product. None of
the existing testbenches caught it because they all target
`inference_accelerator` (v1) — v4 was never simulated.

**2. The 12-bit bound doesn't hold at K=64.** Max |product| is (−8)·(−8)=64,
and 12-bit signed tops out at 2047 — adversarial inputs overflow at
accumulation #32 (32×64=2048), before the claimed-safe 64 (and the double
count halves that again). Also: `k_dim`/addresses are 6-bit, so the core can
address 64 of the 4096-deep SRAMs the accelerator instantiates (1.6%).

Neither finding dents the PPA results — the flow doesn't care what the logic
computes — but "same compute" needs these fixed.

## v9 — correct, unlimited K, same fast path

Hierarchical accumulation: a fast 12-bit *chunk* accumulator (identical
per-cycle path to v4: mult + 12-bit add) folds into a 24-bit wide accumulator
every 16 adds, on its own cycle. Bound is provable: 16×64 = 1024 ≤ 2047.
24-bit covers K ≤ 131,071 (d_ff 22016 with 6× margin); k_dim/addr widened to
16 bits so the full SRAM depth is usable. Single-add control (bug 1 fixed);
restartable without reset (see below).

## v10a — streaming control: ~2× sustained throughput

v4/v9 alternate FETCH/COMPUTE: one element per 2 cycles. The SRAM read is
pipelined, so v10 issues an address every cycle and enables the accumulate
exactly at read latency: one add per cycle. Measured (tb): K=37 in 43 cycles
vs v9's 77. Peak TOPS becomes sustained TOPS.

## v10b — carry-save chunk: shorter critical path

The chunk pair lives in redundant sum/carry form; the per-cycle path is one
3:2 compressor level instead of a 12-bit carry chain, resolved only at the
once-per-16-cycles registered fold. (The earlier `mac_csa` branch resolved
sum+carry combinationally on the output every cycle, which kept a CPA in the
timing cone — that is why it didn't win.) v10b is bit-identical to v10a in
all tests.

## Restart bug (found in our own v9/v10, inherited from v4's FSM shape)

DONE was a terminal state: first operation works, every later `start` is
silently ignored until hard reset. Fixed in v9/v10 (DONE + start → CLEAR);
v4 has the same shape. Repro of the class: `tb/tb_v10_edges.v` (back-to-back
runs without reset).

## Verification

`tb/tb_v9_v10.v` (v9/v10a/v10b vs computed-expected: ones, chunk-exact,
adversarial-overflow K=32, random K=37 — 12/12 PASS, cycle counts printed)
and `tb/tb_v10_edges.v` (K=1, no-reset reuse, max-negative K=64 — PASS after
the restart fix).

## Physical results (ORFS nangate45, frozen 26Q2, util-limited by pins)

v4 constraint sweep (unchanged RTL): closes 1.33 ns (+0.03) → **752 MHz
confirmed**; pushed harder the path compresses to ~1.13 ns → **~885 MHz**
ceiling (+18% from constraint honesty alone).

v9 / v10a / v10b sweep at 0.66–1.33 ns targets: RUNNING — table to be filled
in from `reports/nangate45/kimi_*/base/6_finish.rpt` when the fixed-RTL runs
land. Note die area is pad-limited for the 24-bit-bus variants (6.1K pins on
a bare core); cell area from synthesis is the fair area comparison.
