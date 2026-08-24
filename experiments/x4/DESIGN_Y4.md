# X4-Y4: registered two-slice fold at 820 MHz

Y3 strict-passed 780 MHz and reached 837.683 MHz extracted fmax. Its final worst path ran from `chunk_accum[57][1]` to `wide_accum[57][16]` through 21 combinational cells, exposing the signed 24-bit fold carry chain as the new bottleneck.

Y4 splits that fold across two register-to-register cycles. `S_FOLD_LO` adds the low 12 bits and registers both the low result and carry. `S_FOLD_HI` adds the sign-extension word and registered carry into the upper 12 bits. This preserves exact modulo-24-bit two's-complement addition while halving the carry depth. New cumulative executable rules require both registered slices and reject the old direct 24-bit fold.

The target is 820 MHz, or 1.219512 ns. This is monotonically above 780 MHz and below Y3's measured 837.683 MHz extracted ceiling.

The change adds one cycle per fold. Output count and order, SRAM request behavior, exactly-once consumption, external interface, and signed INT4 result remain unchanged. Local Icarus regression passes K=7/0/13, fold boundaries K=15/16/17/31/32/33, signed extrema, busy-start, reset/restart, tail flush, and K=65535. All 16 cumulative executable lint/proof checks, Verilator lint, and Yosys structural check pass.

The real full Nangate45 flow completed with `FLOW_RC=0` but is a strict FAIL. Final extraction achieved 900.93 MHz at the 820 MHz target, with +0.109536 ns setup WNS, zero setup TNS, +0.0229796 ns hold WNS, zero setup/hold/slew/fanout violations, zero DRC, and zero antenna violations. The fold split therefore removed Y3's 24-bit carry bottleneck. The new worst setup path is a 21-cell 12-bit chunk-accumulator path from `chunk_accum[186][0]` to `chunk_accum[186][11]`.

Strict signoff failed only on two extracted max-capacitance violations. `wire57969/Z` measures 356.23 against a 242.31 limit, and `wire57973/Z` measures 270.23 against the same limit. Y5 will retain the report-proven architecture, strengthen capacitance repair beyond Y4's `CAP_MARGIN=22`, and target 880 MHz, monotonically above 820 MHz while retaining 20.93 MHz of margin below Y4's measured 900.93 MHz ceiling.
