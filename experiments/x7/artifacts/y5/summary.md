# X7 Y5 1 GHz closure

Y5 closes the 1.0 ns module-level target while preserving exact two-token behavior and exactly 32 SRAM macros.

The complete unit suite passes. The full two-token output and persistent-state golden test passes in 128,820 cycles.

## Changes from Y4

- Diagnosed the Y4 norm critical path through the replicated 8x9 scale multiplier and immediate saturation logic.
- Added a `SCALE_QUANT` pipeline state between scale-product generation and saturation/residual addition.
- Tightened ABC mapping, buffering, and sizing from a 1.1 ns objective to 0.95 ns.
- No state-engine or MAC RTL changes were needed. The tighter mapping objective brought both below 1.0 ns after the norm path was structurally split.

## Functional result

- Unit tests: pass
- Two-token output golden: pass
- Two-token persistent state golden: pass
- Cycles: 128,820
- SRAM macros: exactly 32

## Synthesis result

- Flow: `flow/synth_y5.ys`
- ABC script: `flow/abc_y5_margin.script`
- Library: Nangate45 typical
- Mapping objective: 0.95 ns
- Closure target: 1.0 ns
- Logic area excluding SRAM macro area: 149,504.502 um^2
- Mapped netlist: `artifacts/y5/x7_mapped.v`
- Peak synthesis memory: 737.62 MB
- User CPU time: 18.56 s

| Module | Y4 delay | Y5 delay |
|---|---:|---:|
| activation_sram | 0.19784 ns | 0.19784 ns |
| conv_unit_serial | 0.82432 ns | 0.82432 ns |
| intermediate_sram | 0.38808 ns | 0.38808 ns |
| mac_array_16x16 | 1.04738 ns | 0.92882 ns |
| requant | 0.25417 ns | 0.25417 ns |
| state_sram | 0.22232 ns | 0.22232 ns |
| state_stream_controller | 0.60468 ns | 0.62438 ns |
| state_word_engine | 1.09841 ns | 0.95519 ns |
| streaming_norm | 1.11092 ns | 0.94651 ns |
| weight_sram | 0.23076 ns | 0.23076 ns |
| x7_controller | 0.27766 ns | 0.27766 ns |
| x7_top | 0.53110 ns | 0.53110 ns |

The worst module is now `state_word_engine` at 0.95519 ns, leaving 44.81 ps of margin to 1.0 ns. The corresponding module-level estimate is 1,046.9 MHz. Norm is 0.94651 ns and MAC is 0.92882 ns.

Versus Y4, worst delay falls 14.02%, logic area rises 1.27%, and two-token latency rises by only 16 cycles, or 0.012%. The aggressive 0.95 ns mapping objective is missed by 5.19 ps in the state engine, but every module closes the actual 1.0 ns target.

These are ABC module-level, pre-layout estimates with no extracted interconnect. Physical implementation and signoff STA are required before claiming 1 GHz silicon closure.
