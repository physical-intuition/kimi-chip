# X4 terminal summary

X4 completed all five evidence-driven iterations and stops before X5 as required. It began from the signed 12-bit chunk plus signed 24-bit wide hierarchical-fold architecture, with a separate fold cycle every 16 valid products, tail flushing, exactly-once registered-SRAM response consumption, and verified 16-bit `k_dim` support through K=65,535.

## Trajectory

| Cell | Target | Extracted fmax | Result | Evidence-driven change |
|---|---:|---:|---|---|
| Y1 | 752 MHz | 719.140 MHz | FAIL | Hierarchical 12-to-24-bit fold baseline; failure exposed a redundant request-control comparator rather than an accumulator limit. |
| Y2 | 760 MHz | 783.569 MHz | PASS | Removed the progress-dependent request predicate. |
| Y3 | 780 MHz | 837.683 MHz | PASS | Registered the selected accumulator row to split the combined row/column readout cone. |
| Y4 | 820 MHz | 900.930 MHz | FAIL | Split the 24-bit fold carry into registered low/high 12-bit additions; timing passed, but two extracted max-capacitance violations remained. |
| Y5 | 880 MHz | 909.621 MHz | PASS | Raised `CAP_MARGIN` from 22 to 30 based on Y4's electrical evidence. |

Y5 final extraction reports +0.037041 ns setup WNS, zero setup TNS, +0.0292948 ns hold WNS, zero setup/hold/slew/fanout/max-capacitance violations, zero DRC, and zero antenna net/pin violations. Its final worst path is `chunk_accum[156][1]` to `wide_accum[156][11]`, with 19 combinational cells and maximum observed path fanout 16.

## Learned executable rules

The cumulative X4 harness ends with 18 passing checks. The evidence-backed rules reject global shift drains, behavioral SRAM arrays, unproved accumulator widths, duplicate registered-response accumulation, progress-dependent request decode, direct combined row/column readout, and a direct 24-bit fold carry. They require the signed 12-bit/24-bit hierarchy, fold-boundary and K=65,535 regressions, reset/restart and busy-start coverage, disk preflight, parseable flow markers, and report-driven electrical repair.

## Successful and failed transforms

The hierarchical fold moved the critical path out of the old wide per-cycle accumulator but did not by itself close 752 MHz because request control became critical. Removing that comparator closed the first higher target. Registering readout selection raised extracted fmax by 54.114 MHz. Splitting the fold carry raised it by another 63.247 MHz, but the first physical implementation failed strict signoff on two capacitance violations. `CAP_MARGIN=30` repaired both violations and produced the terminal 880 MHz pass.

The remaining bottleneck is the chunk-to-low-wide-accumulator arithmetic/control cone. It is evidence for a future harness, not permission to predesign X5. X5 remains pending with all five cells untouched.
