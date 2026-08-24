# X7 Y2 SRAM-streaming result

Y2 is functionally exact and synthesis-clean, but it does not meet the 2.0 ns target.

The complete unit suite passes. The full two-token top test passes bit-exact output and persistent-state checks in 74,480 cycles with exactly 32 `fakeram45_512x64` macros.

The top no longer contains the projection, convolution, state, diff, or final-output RF mirrors. State update is streamed through an 8-lane word engine with one reused 32-entry accumulator. RMSNorm makes two SRAM passes and writes residual-added output directly to activation SRAM. There is no active `state_update`, `reduction_accum32`, `norm_unit`, or 1024-bit norm vector in `x7_top`.

Yosys 0.33 plus ABC completed successfully against Nangate45 with a 2.0 ns target. The mapped netlist is `artifacts/y2/x7_mapped.v`. Logic area excluding SRAM macro area is 162,887.228 um^2. Peak memory was 988.84 MB and synthesis used 25.34 seconds user CPU time.

ABC module delays are:

| Module | Delay |
|---|---:|
| activation_sram | 0.84249 ns |
| conv_unit_serial | 1.82736 ns |
| intermediate_sram | 0.85227 ns |
| mac_array_16x16 | 1.53429 ns |
| requant | 0.25417 ns |
| state_sram | 0.59726 ns |
| state_stream_controller | 6.71931 ns |
| state_word_engine | 5.08579 ns |
| streaming_norm | 2.43749 ns |
| weight_sram | 3.28332 ns |
| x7_controller | 0.30254 ns |
| x7_top | 8.17050 ns |

Compared with Y1, top delay fell from 164.64723 ns to 8.17050 ns, about 20.15x, and logic area fell 57.57%. The serialization cost raised two-token latency from 18,194 to 74,480 cycles, about 4.09x.

The next timing priorities are the top-level 8.17 ns control/data mux path, the 6.72 ns state controller path, the 5.09 ns state word engine, then streaming norm at 2.44 ns and the unchanged 3.28 ns weight wrapper. This is a real architectural improvement, not timing closure.

No commit or push was made.
