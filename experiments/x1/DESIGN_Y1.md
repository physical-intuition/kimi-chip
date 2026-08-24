# X1-Y1 Design Notes

The baseline computes a signed INT4 outer product every active cycle. A 64-bit activation word and a 64-bit weight word each hold sixteen packed INT4 lanes. Their Cartesian product updates 256 independent 24-bit accumulators.

The activation and weight ports each address 4096 64-bit words, exactly 32 KiB. Reads are synchronous with one cycle of latency. Results are serialized as 256 24-bit writes through an output SRAM interface whose address space exceeds the requested 32 KiB.

The controller has idle, run, and drain phases. It issues one activation/weight pair per cycle, tracks returned words with a valid pipeline, then writes all 256 results. A new operation clears the accumulator array. `done` pulses after the final output write.

The 24-bit accumulator is conservative for the complete 12-bit K range. The largest magnitude product is 64, so 4096 products need at most 262144 magnitude, well within signed 24-bit range.

Verification uses a self-checking Icarus Verilog testbench with nonuniform signed operands over seven K steps. It checks every one of the 256 output words against a software-style reference calculation.

The SRAM arrays are not instantiated as flip-flops. X1-Y1 measures controller and compute logic while preserving explicit ports for three physical SRAM blocks. Consequently, reported standard-cell area does not include the 96 KiB SRAM macro area and must not be compared to Kimi's 4 mm² full-chip area as though it did.
