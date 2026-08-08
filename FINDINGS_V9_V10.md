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

| | inference_accelerator (control arm) | fullchip_v10 |
|---|---|---|
| Memories | flops (no macro path) | 16x fakeram45_512x64 |
| Routed DRC | **0 violations** | **0 violations** |
| Worst slack @ 1.33 ns | -1.67 ns -> path 3.00 ns -> **~333 MHz** | **-0.02 ns -> fmax ~741 MHz** |
| Pushed @ 1.20 ns | - | -0.12 ns -> **ceiling ~758 MHz** |
| Critical path | sram rdata reg -> row14/col13 32b acc | mem rdata reg -> row7/col7 12b chunk |
| Sustained MACs | 256 x f/2 | 256 x f (streaming) |
| vs measured baseline | 1x | **~2.3x clock, ~4.6x sustained compute** |

Final numbers are from the bank-select-fixed RTL (see tb_fullchip_banks.v:
a select-pipeline off-by-one was caught by bank-crossing tests and fixed;
physical results re-measured, delta vs the pre-fix netlist within 20 ps).
The routed critical path is the read-data broadcast (mem rdata_q register ->
interior MAC row7/col7 through mult+add): the measured ~9% full-chip tax vs
the 833 MHz core ceiling. Known remedy (unbuilt): register the broadcast
per column group ("v12"), absorbed by RD_LAT=4.

Verification: bit-exact vs expected at K=300/700/1030 including bank
crossings (1 MAC/cycle through the real memory system).
Memory timing triple-sourced: platform lib clk->Q 0.305 ns, OpenRAM-compiled
256x64 measured 0.34 ns, and a deliberately 2.4x-pessimistic model (0.83 ns)
used for the conservative bound.

Control arm (measured): the unmodified inference_accelerator, exact same
flow and constraints, routes DRC-clean at a 3.00 ns path = ~333 MHz -- the
same order as the ~250 MHz Factory observation (different flow snapshot).
Its critical path is the same *class* as ours -- read-data register into
the array interior -- but 1.67 ns worse: 32-bit single-level accumulate,
no chunked add, and a flop-sea floorplan stretching the broadcast. So the
memory macros, the hierarchical 12b chunk, and the compact floorplan are
each visible in the delta.

## v12 + floorplan sweep: the last 75 MHz, dissected

v12 (rtl/) registers the read-data broadcast per 4-bit lane (32 lane
registers placeable beside the strips they feed; read latency 3 -> 4).
Verified with lane-DISTINCT data across bank crossings, residual chunks,
and restart (tb_fullchip_v12.v, tb_v12_fill.v). Physically it moved the
critical path exactly as designed -- startpoint is now the lane register,
not the memory interface -- and changed fmax by nothing (-0.115 vs v10's
-0.12 at 1.20 ns): the broadcast was riding repeaters nearly free, and
the binding cost is the array's own span (1.06 ns from lane register Q
through a 16-MAC strip's fanout + mult + 12b add). Deeper pipelining is
not the lever; geometry is.

Three controlled axes confirm it (all v12 RTL, 1.20 ns target, routed
DRC-clean unless noted):

Effort: a 1.10 ns-target rebuild lands -0.22 -> the same 1.32 ns path.
The tools are saturated; constraint pressure buys zero.

Arrangement: pinning the 16 macros to the left/right core edges
(MACRO_PLACEMENT_TCL, pins mirrored inward -- flush-R0 pins facing the
die edge fail GRT-0116) is fmax-neutral: -0.12 (u25), -0.11 (u35).
Auto placement already keeps each bank near its consumers. Shrinking
keep-outs instead (halo 5, channel 10) fails PDN-0179: the straps need
the channels.

Utilization (auto placement): 25 -> -0.115, 35 -> -0.10, 40 -> -0.08,
50 -> -0.11. Shorter die-span wins until macro crowding (29% of core at
util 50) gives it back.

v12 full-chip result: **util 40 -> 1.28 ns path -> ~781 MHz**, routed
DRC-clean with all 16 macros -- 3.1x the measured 333 MHz baseline,
~6x its sustained compute, ~52 MHz under the core-only 833 ceiling.
The residue is the irreducible cost of a 16x16 array living on the same
die as 64 KB of SRAM at this node.

## v13: paired reads + registered product = 512 MACs/cycle at 800 MHz

Once fmax saturated, the remaining lever was work per cycle. v13 composes
two changes (rtl/, both falling directly out of the v12 postmortem):

- The same 16 macros re-grouped as 2x4 banks per operand (even/odd
  element): a pair index reads both groups at once -> 128 bits/operand/
  cycle, no bank conflicts, single-port macros and 64 KB unchanged.
- v11's registered product, widened to the pair: prod_q <= a0*b0 + a1*b1
  (9b); the 13-bit chunk add (16 pair-adds x 128 = 2048 <= 4095) and the
  24-bit fold each get their own cycle. Odd k_dim: the final half-pair's
  odd activation slot is zeroed through the lane register.

Sim: lane-distinct data, K=1/2/37/700/1029/1030 at scattered
accumulators, restart-after-DONE -- all bit-exact; K=700 completes in
361 cycles = K/2+11, the machine-checked proof of 2 elements/lane/cycle.

Measured (util 40, 1.20 ns target): **-0.05 -> 1.25 ns -> 800 MHz,
routed DRC-clean**. The critical path is lane register -> prod_q --
the chunk add is off the worst cycle, exactly as designed; fmax IMPROVED
while the netlist grew 50% (die 1.44 mm2 vs v12-u40's 1.20).

| | control arm (measured) | v12 u40 | v13 u40 |
|---|---|---|---|
| clock | 333 MHz | 781 MHz | **800 MHz** |
| MACs/cycle | 128 | 256 | **512** |
| sustained | ~43 GMAC/s | ~200 GMAC/s | **~410 GMAC/s (0.8 INT4 TOPS)** |
| die | 14.13 mm2 | 1.20 mm2 | 1.44 mm2 |
| GMAC/s/mm2 | 3 | 167 | **285** |

Net vs the measured baseline: ~9.6x sustained compute in ~1/10th the
silicon, every number from a routed, DRC-clean signoff on the same flow.

## v14: ping-pong tiles -- sustained = peak

v13's honest weakness was utilization: the host port is phase-muxed with
compute, so reloading between passes costs 3-4x the compute time and
sustained throughput across back-to-back tiles is ~1/3 of peak. v14
splits each operand memory into two TILES (2 groups x 2 banks x 512 =
2048 elements each): the host writes one tile while the core streams the
other -- different physical banks, so the single-port macros never see a
conflict and loads run at full rate DURING compute. A new accum start
mode preserves accumulators across passes, so K spans tiles: usable K
rises from the 4096-element memory bound to the arithmetic bound
(131,071 elements).

Sim: 121 elements loaded into tile 1 concurrently with a bit-exact
700-element pass on tile 0; cross-pass accumulation matches the K=1030
reference for even and odd split points; clean restart drops state.

Measured (util 40, 1.20 ns target): **-0.02 -> 1.22 ns -> ~820 MHz,
routed DRC-clean** -- the retiling slightly IMPROVED timing over v13.

Final chip: **~820 MHz x 512 MACs/cycle = ~420 GMAC/s (0.84 INT4 TOPS),
sustained ~= peak for pipelined workloads, 1.44 mm2** -- roughly 10x the
measured baseline's compute in a tenth of its silicon, and ~3x v13's
sustained rate. Known next bottleneck (documented, unbuilt): the 64-bit
host load port itself; a wider or burst-mode port is the natural v15.

## sys16 (v2 arc, milestone 1): systolic array -- scale-invariance measured

Every broadcast experiment said the same thing: the array's geometric
span is the wall, and it grows with array size. sys16 (rtl/
systolic_core16.v) is the weight-stationary answer: weights sit in PEs,
activations lane-walk out of per-row word buffers (row skew = a rippling
start pulse), psums flow south, bottom units accumulate -- every signal
moves ONE PE pitch per cycle, fanout 1, zero broadcast. Same
C[r][c] = sum_k A[k][r]*W[k][c] as every version; sim 20/20 bit-exact
against the shared reference including residual-chunk zero-row gating,
accum passes, restart.

Two measured iterations at a 1.00 ns target (util 40, DRC-clean both):
- First run: -0.18 (~847 MHz). Critical path was NOT the array -- it was
  the bottom accumulator's indexed read-modify-write (index decode ->
  16:1 mux -> 24b add -> decoded writeback).
- Accesses are strictly sequential in r, so the indexed file became a
  ROTATING RING (rotate each active cycle, add into the tail from the
  fixed head; 16 rotations per window = identity). Result: **-0.07 ->
  1.07 ns -> ~935 MHz**, critical path now wrow -> mult -> 12b add -> P
  register, ENTIRELY INSIDE ONE PE. No wire crossing, no fanout, no
  geometric term: a 64x64 array has the same worst path. That is the
  scaling property no broadcast floorplan could buy, now measured.

M1 is deliberately stop-and-load (~64 MACs/cycle sustained): it exists
to measure the clock. The roadmap it unlocks: M2 = shadow weight regs +
row prefetch (swap pulse rides the pipeline) -> zero stalls, 256
MACs/cycle at ~935 MHz using the same 2 words/cycle the memories supply;
M3 = paired PEs (512/cycle) and wider arrays (32x32 -> 2048/cycle at an
unchanged critical path) -- the 10-100x axis.

## Exact reproduction commands

Everything ran in the stock ORFS docker image (26Q2-era; any 26Q2 build
works - pin by digest, not tag). No flow scripts modified or mounted.

Stage a design (example: the full chip):

    # RTL into the flow tree (files from this repo's rtl/)
    cp rtl/int4_mac_v9.v rtl/mac_array_v9.v rtl/compute_core_v10.v \
       rtl/fullchip_v10.v  OpenROAD-flow-scripts/flow/designs/src/kimi_fullchip/
    # config + SDC from this repo's flow/
    cp -r flow/nangate45/kimi_fullchip \
       OpenROAD-flow-scripts/flow/designs/nangate45/

Run the flow (one command per design; ~10-30 min each on a big box):

    docker run --rm \
      -v $PWD/OpenROAD-flow-scripts/flow:/OpenROAD-flow-scripts/flow \
      -w /OpenROAD-flow-scripts/flow \
      openroad/orfs:<26q2-digest> \
      bash -c "source ../env.sh && \
               make DESIGN_CONFIG=designs/nangate45/kimi_fullchip/config.mk"

Read the result:

    grep "worst slack max" flow/reports/nangate45/kimi_fullchip/base/6_finish.rpt
    grep "Number of violations" flow/logs/nangate45/kimi_fullchip/base/5_2_route.log
    # fmax = 1 / (clock_period - worst_slack); clock_period is set in the
    # design's constraint.sdc (1.33 ns for the full chip = v4's 752 MHz)

Same pattern for every design in flow/nangate45/ (the sweep points differ
only in SDC period + ABC_CLOCK_PERIOD_IN_PS). The v4 rows need only her
existing rtl/int4_mac_v4.v, mac_array_v4.v, compute_core_v4.v staged to
designs/src/kimi_v4/.

Testbenches (Verilator 5.x):

    verilator --binary --timing -Wno-fatal tb/tb_v4_count.v \
      rtl/int4_mac_v4.v rtl/mac_array_v4.v rtl/compute_core_v4.v -o tbc
    ./obj_dir/tbc     # prints 7 - the v4 double-count repro (expected: 4)

    verilator --binary --timing -Wno-fatal tb/tb_v9_v10.v rtl/int4_mac_v9.v \
      rtl/mac_array_v9.v rtl/compute_core_v9.v rtl/int4_mac_v10.v \
      rtl/mac_array_v10.v rtl/compute_core_v10.v -o tb10
    ./obj_dir/tb10    # 12/12 PASS with cycle counts (v10a ~2x v9 throughput)
