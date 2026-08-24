# X5-Y1

X5-Y1 was not planned before X4 completed. `harness/derive_y1.py` ingests all five X4 terminal trials, hashes their raw timing, RTL, and design evidence, verifies the actual RTL/config transitions, and emits `x4_learning.json` plus `y1_policy.json`.

X4-Y5's final extracted max setup path is a 19-cell cone from `chunk_accum[156][1]` to `wide_accum[156][11]`. This proves the remaining bottleneck is the low 12-bit fold carry chain. X5-Y1 splits that addition into registered 6-bit low and upper-low slices before the existing high 12-bit signed fold. All earlier X4 repairs remain intact.

The target was generated only after ingestion. X4-Y3 to Y4 measured the gain from the prior report-driven fold split. The harness conservatively applies 40% of that relative gain to X4-Y5's 909.621 MHz extracted ceiling, deriving 937.092 MHz and 1.067131082 ns. No frequency constant is embedded in the flow source; `generate_flow.py` reads the generated policy.

The inherited functional regression passes K=0/7/13, fold boundaries 15/16/17/31/32/33, signed extrema, busy-start and k_dim latching, reset abort and clean restart, exactly-once external memory requests, tail flush, and K=65535. The 18 executable structural/provenance checks pass, as do Verilator and Yosys.

Y2-Y5 do not exist and remain unplanned.
