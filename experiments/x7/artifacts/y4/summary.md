# X7 Y4 timing-margin result

Y4 increases module-level timing headroom while preserving the exact two-token behavior and exactly 32 SRAM macros.

The complete unit suite passes. The full two-token output and persistent-state golden test passes in 128,804 cycles.

## Changes from Y3

- Replaced the single-cycle convolution gate path with four registered stages: products, pair reductions, final reductions, and quantize/clamp.
- Replaced the two-stage 32-product projection MAC with a deeply pipelined tree. Every reduction level ends at a register, followed by registered final sum and accumulate/saturate stages.
- Tightened the ABC mapping, high-fanout buffering, and sizing objective from 2.0 ns to 1.1 ns in `flow/abc_y4_margin.script`.

## Functional result

- Unit tests: pass
- Two-token output golden: pass
- Two-token persistent state golden: pass
- Cycles: 128,804
- SRAM macros: exactly 32

## Synthesis result

- Flow: `flow/synth_y4.ys`
- ABC script: `flow/abc_y4_margin.script`
- Library: Nangate45 typical
- Mapping objective: 1.1 ns
- Original closure target: 2.0 ns
- Logic area excluding SRAM macro area: 147,633.724 um^2
- Mapped netlist: `artifacts/y4/x7_mapped.v`
- Peak synthesis memory: 769.52 MB
- User CPU time: 27.56 s

| Module | Y3 delay | Y4 delay |
|---|---:|---:|
| activation_sram | 0.19784 ns | 0.19784 ns |
| conv_unit_serial | 1.70773 ns | 0.82432 ns |
| intermediate_sram | 0.38808 ns | 0.38808 ns |
| mac_array_16x16 | 1.46156 ns | 1.04738 ns |
| requant | 0.25417 ns | 0.25417 ns |
| state_sram | 0.22232 ns | 0.22232 ns |
| state_stream_controller | 0.64459 ns | 0.60468 ns |
| state_word_engine | 1.34146 ns | 1.09841 ns |
| streaming_norm | 1.33109 ns | 1.11092 ns |
| weight_sram | 0.23076 ns | 0.23076 ns |
| x7_controller | 0.27766 ns | 0.27766 ns |
| x7_top | 0.53110 ns | 0.53110 ns |

The worst reported module moves from convolution at 1.70773 ns to streaming norm at 1.11092 ns. Margin to the original 2.0 ns target increases from 0.29227 ns to 0.88908 ns, a 3.04x increase. The worst module delay falls 34.95%, corresponding to roughly 900.2 MHz at this module-level estimate.

The tradeoff is modest: logic area increases 5.85% and two-token latency increases 4.79% versus Y3. The 1.1 ns mapping objective is missed by 10.92 ps in `streaming_norm`, but every module remains below 1.12 ns and has at least 0.889 ns margin to the actual 2.0 ns requirement.

These are ABC module-level, pre-layout estimates with no extracted interconnect. Physical implementation and signoff STA are still required before treating 900 MHz as a silicon frequency.
