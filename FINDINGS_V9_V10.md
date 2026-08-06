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

## v9 — correct, overflow-proof for all expressible K, same fast path

Hierarchical accumulation: a fast 12-bit *chunk* accumulator (identical
per-cycle path to v4: mult + 12-bit add) folds into a 24-bit wide accumulator
every 16 adds, on its own cycle. Bound is provable: 16×64 = 1024 ≤ 2047.
The binding K limit is the 16-bit k_dim (65,535) — and 65,535×64 ≤ 2²³−1, so
every expressible K is adversarially overflow-proof in the 24-bit accumulator
with 2× margin: the accumulator can never be the binding constraint. Covers
d_ff 22016; addresses reach the full instantiated SRAM depth. Single-add control (bug 1 fixed);
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

Corrected sweep (fixed RTL + corrected SDC, all routed DRC-clean), implied
ceilings from best critical path across three clock targets each:

| Variant | Best path | Ceiling | Notes |
|---|---|---|---|
| v4 | 1.13 ns | ~885 MHz | fastest — but double-counts, K<=64 |
| v10a | 1.20 ns | ~833 MHz | correct, 1 MAC/cycle: ~1.9x v4 sustained compute |
| v10b | 1.28 ns | ~781 MHz | CSA disproven: its fold (resolve+24b add) is its own critical path |
| v9 | 1.29 ns | ~775 MHz | correct baseline |

Routed critical paths (from 6_finish.rpt): v10a binds on the input-data ->
multiply -> add path; v10b binds register-to-register on its own fold. v11
(registered product + two-stage fold, in rtl/) targets both; unmeasured.

## Full chip: the 250 MHz question, answered

Factory full-chip global placement sticks at ~250 MHz because its flow has no
SRAM macro path: the 96 KB of sram_sp buffers synthesize to ~500 Kbit of
flip-flops plus 4096:1 read-mux ladders (~12 logic levels before the MAC).
fullchip_v10 (rtl/) replaces them with 16x fakeram45_512x64 platform hard
macros (64 KB), a 3-cycle pipelined read path, and a phase-muxed host port.
Result on Nangate45, frozen 26Q2, clock set to 1.33 ns (= v4's 752 MHz):

| | Factory full chip | fullchip_v10 |
|---|---|---|
| Memories | flops (no macro path) | 16x fakeram45_512x64 |
| Routed DRC | - | **0 violations** |
| Worst slack @ 1.33 ns | - | **-0.00 ns -> fmax ~752 MHz** |
| Sustained MACs | 256 x f/2 | 256 x f (streaming) |
| vs 250 MHz baseline | 1x | **~3x clock, ~6x sustained compute** |

Verification: bit-exact vs expected at K=300 through all bank boundaries
(310 cycles = K+10, confirming 1 MAC/cycle through the real memory system).
Memory timing triple-sourced: platform lib clk->Q 0.305 ns, OpenRAM-compiled
256x64 measured 0.34 ns, and a deliberately 2.4x-pessimistic model (0.83 ns)
used for the conservative bound. An 830 MHz-target run and a control-arm run
of the unmodified inference_accelerator (memories as flops, same flow) are
in flight to complete the ceiling and baseline rows.
