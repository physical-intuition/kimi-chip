# X7 Y3 timing-closure result

Y3 is functionally exact and closes the 2.0 ns Nangate45 target under Yosys 0.33 plus ABC timing-driven mapping, buffering, and sizing.

The complete unit suite passes. The full two-token top test passes bit-exact output and persistent-state checks in 122,916 cycles with exactly 32 `fakeram45_512x64` macros.

## Architecture changes

- Replaced binary high-fanout control in the top, state controller, and norm controller with one-hot phase/state encodings.
- Converted the large datapath controllers to asynchronous-reset flops so reset does not sit in every synchronous D-path mux.
- Pipelined the eight-lane state word engine and decomposed the wide `beta*k*d` path into registered partial products.
- Split state diff generation into requantize, subtract/saturate, and registered write stages.
- Registered intermediate-vector response selection.
- Replaced the weight SRAM's wide matrix output mux with a registered two-level 2:1 tree.
- Pipelined norm square reduction, Newton-Raphson products, scale, residual add, and output write stages.
- Reworked top arbitration by phase and removed timing-heavy dynamic conv write assembly from the SRAM command path.
- Added explicit ABC high-fanout buffering and timing-driven cell upsizing/down-sizing in `flow/abc_y3_close.script`.

## Functional result

- Unit tests: pass
- Two-token output golden: pass
- Two-token persistent state golden: pass
- Cycles: 122,916
- SRAM macros: exactly 32

## Synthesis result

- Flow: `flow/synth_y3.ys`
- ABC script: `flow/abc_y3_close.script`
- Library: Nangate45 typical
- Target: 2.0 ns
- Logic area excluding SRAM macro area: 139,480.558 um^2
- Mapped netlist: `artifacts/y3/x7_mapped.v`
- Peak synthesis memory: 767.62 MB
- User CPU time: 18.33 s

| Module | Delay |
|---|---:|
| activation_sram | 0.19784 ns |
| conv_unit_serial | 1.70773 ns |
| intermediate_sram | 0.38808 ns |
| mac_array_16x16 | 1.46156 ns |
| requant | 0.25417 ns |
| state_sram | 0.22232 ns |
| state_stream_controller | 0.64459 ns |
| state_word_engine | 1.34146 ns |
| streaming_norm | 1.33109 ns |
| weight_sram | 0.23076 ns |
| x7_controller | 0.27766 ns |
| x7_top | 0.53110 ns |

The worst reported module is `conv_unit_serial` at 1.70773 ns, leaving 0.29227 ns margin to the 2.0 ns target. This corresponds to roughly 585.6 MHz at the reported module delay.

Compared with Y2, Y3 cuts top delay from 8.17050 ns to 0.53110 ns, another 15.38x improvement. Logic area falls 14.37%, from 162,887.228 to 139,480.558 um^2. Added pipeline stages increase two-token latency from 74,480 to 122,916 cycles, or 1.65x.

The delay numbers are ABC module-level, pre-layout estimates with no extracted interconnect. Physical implementation and signoff STA are still required before calling 500 MHz silicon-closed.

No commit or push was made.
