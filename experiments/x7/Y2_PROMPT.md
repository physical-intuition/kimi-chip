Implement X7 Y2 in this directory. Read X7_SPEC.md, X7_HARNESS.md, Y1_CORRECTED_PROMPT.md, artifacts/y1/summary.md, trials.jsonl, and all current RTL/testbench/flow files first.

Y1 is functional and synthesizes with exactly 32 fakeram45_512x64 macros, but timing is not closed. Preserve the exact top-level interface, bit-exact Python golden behavior, two-token state behavior, and exactly 32 macros total. Do not add macros. Do not commit or push.

Y2 priority is a real SRAM-streaming architecture, not keep attributes or dead macro mirrors.

1. Eliminate top-level RF mirrors causing the 164.647 ns x7_top path. Remove xrf/yrf/arf/brf/drf/frf and K/V/Q/O RF mirrors from the synthesized datapath. K/V/Q/O results must be read back from the four intermediate SRAM macros. Store x, y, alpha/beta, diff, normalized/final values in unused addresses of the existing four activation SRAM macros, with an explicit non-overlapping address map. Account for fakeram synchronous read latency. Prefer 128-bit beat streaming and lane extraction with small registered windows. Do not reconstruct 1024-bit buses or inferred 128-entry arrays at module boundaries.

2. Refactor state_update from 32-lane combinational logic into a serialized or pipelined lane engine that meets 2 ns. It can add cycles. Preserve exact fixed-point arithmetic and state contents. Stream K/Q/diff values from SRAM/register windows.

3. Refactor norm into SRAM-streaming iterative operation. It must consume and emit 16 INT8 lanes per activation SRAM beat over 8 beats, accumulate squares iteratively, perform the same 3 NR iterations, then write scaled/residual values back beatwise. Do not use 1024-bit input/output ports or 128-element inferred arrays.

4. Keep the pipelined balanced-tree MAC and serialized conv. Y1 measured MAC 1.534 ns and conv 1.827 ns.

Create artifacts/y2. Add or adapt focused unit tests for synchronous SRAM scheduling and end-to-end two-token golden/state behavior. Run unit and top tests. Then run Yosys+ABC with Nangate45 and the current timing script, saving artifacts/y2/synth.log and mapped netlist. Verify the stat contains exactly 32 fakeram macros. Extract real per-module ABC delay values. Append one honest JSON object to trials.jsonl and write artifacts/y2/summary.md. If timing does not close, report exact remaining paths and do not claim success.

Do not change unrelated experiments. Do not commit or push.