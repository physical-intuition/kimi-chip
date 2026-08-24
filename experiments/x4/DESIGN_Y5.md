# X4-Y5: extracted-capacitance repair at 880 MHz

Y4's registered two-slice fold removed the 24-bit carry bottleneck and achieved 900.93 MHz extracted fmax at an 820 MHz target. Setup, hold, slew, fanout, DRC, and antenna checks were clean, but strict signoff failed on two final extracted max-capacitance violations. `wire57969/Z` measured 356.23 against a 242.31 limit, and `wire57973/Z` measured 270.23 against the same limit.

Y5 preserves Y4's RTL and full latency-aware functional contract. Its report-driven physical-design change raises `CAP_MARGIN` from 22 to 30, a margin already demonstrated to eliminate extracted capacitance violations in X2. A new cumulative executable rule requires the Y4 electrical failure to be cited and the stronger margin to be active.

The target is 880 MHz, or 1.136364 ns. This is monotonically above Y4's 820 MHz target while retaining 20.93 MHz below Y4's measured 900.93 MHz extracted ceiling. The target is derived from the actual final report rather than a preset ladder.

Local validation passes all 18 cumulative executable lint/proof checks, Icarus functional simulation through K=65,535, Verilator lint, and Yosys structural checking.

The real full Nangate45 flow completed with `FLOW_RC=0` and strict PASS. Final extraction achieved 909.621 MHz at the 880 MHz target, with +0.037041 ns setup WNS, zero setup TNS, +0.0292948 ns hold WNS, and zero setup, hold, slew, fanout, or max-capacitance violations. Detailed routing reduced 26,192 initial violations to zero in four repair iterations; final DRC and antenna net/pin counts are zero. The design uses 205,474 um² of standard-cell area, 3,376,130 um of routed wire, 985,858 vias, and an estimated 0.367562 W.

The final worst path starts at `chunk_accum[156][1]` and ends at `wide_accum[156][11]` through 19 combinational cells. Raising `CAP_MARGIN` from 22 to 30 removed Y4's two extracted capacitance violations while also improving area and extracted fmax in this placement seed. Canonical local reports are under `experiments/x4/artifacts/y5`; the full 2.8 GB artifact tree remains preserved on the GCS host. X4 is complete and X5 remains untouched and pending by protocol.
