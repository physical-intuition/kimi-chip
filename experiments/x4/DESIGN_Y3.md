# X4-Y3: registered readout split at 780 MHz

Y2 strict-passed 760 MHz and reached 783.569 MHz extracted fmax. Its final worst path ran from `drain_col[0]` to `out_wdata[12]` through 18 combinational cells, combining row and column selection in one cycle.

Y3 adds `S_DRAIN_LOAD`, which registers all 16 words of the selected accumulator row into `drain_row_data`. `S_DRAIN_WRITE` then selects one column from that registered row. This creates a real register boundary between row and column selection and an executable lint rule rejects the old direct `wide_accum` to `out_wdata` structure.

The target is 780 MHz, or 1.282051 ns. This is monotonically above 760 MHz and just below Y2's measured 783.569 MHz ceiling. It is conservative enough to test whether removing the report-proven path changes the bottleneck without inventing unsupported future targets.

The pipeline adds one row-load cycle for each of 16 rows, 16 cycles total. Output count, address order, external interface, and signed INT4 result are unchanged. The inherited latency-aware regression covers K=7/0/13, K=15/16/17/31/32/33, signed extrema, busy-start, reset/restart, paired registered SRAM requests, tail flush, and K=65535.

Terminal physical evidence is pending.

The real full Nangate45 flow completed with `FLOW_RC=0` and strict PASS. Final extraction achieved 837.683 MHz at the 780 MHz target, with +0.0883312 ns setup WNS, zero setup TNS, +0.0369844 ns hold WNS, and zero setup, hold, slew, fanout, or max-capacitance violations. Detailed routing started with 28,030 violations and finished with zero DRC; antenna net and pin counts are both zero. Final design area is 204,558 um².

The new worst path starts at `chunk_accum[57][1]` and ends at `wide_accum[57][16]` through 21 combinational cells in the signed 24-bit fold carry chain. Y4 splits that addition into registered low/high 12-bit slices before raising frequency.
