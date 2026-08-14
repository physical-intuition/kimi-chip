# X7 Y1 corrected architecture result

Functional RTL and synthesis complete with 32 explicit `fakeram45_512x64` instances. The deterministic two-token end-to-end test matches the Python golden model for outputs and updated state. Unit tests pass. No commit or push was made.

The clean Yosys/Nangate45 run completed in 82.44 CPU seconds with 2098.84 MB peak memory. Logic area excluding unknown SRAM macro area is 383872.846 um^2. The mapped hierarchy contains exactly 32 hard SRAM instances.

The 2.0 ns timing target is not closed. After replacing the MAC chain with a pipeline and balanced tree, MAC delay improved from 4.815 ns to 1.534 ns. Serialized conv improved from 2.771 ns to 1.827 ns. Remaining failures are norm_unit at 8.862 ns, state_update at 10.962 ns, reduction_accum32 at 3.003 ns, weight_sram wrapper at 3.283 ns, and x7_top at 164.647 ns. The top failure is dominated by remaining inferred x/y/alpha/beta/diff/final vector register-file muxes. The four new K/V/Q/O SRAMs are present, but top still mirrors vectors in RFs for arithmetic, so this is not yet a physically valid timing-closed implementation.

Next architecture change must remove those RF mirrors and stream vector words from the four K/V/Q/O macros plus the existing activation macros. Norm must become SRAM-streaming/iterative, and state update must be lane-serialized or pipelined. Calling this timing closed would be false.

Artifacts are `synth_final.log`, `x7_mapped.v`, `unit_tests.log`, and `top_test.log` in this directory.
