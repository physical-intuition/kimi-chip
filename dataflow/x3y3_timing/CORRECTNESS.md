X3Y2 large-dimension correctness iteration, not the historical small-dimension X3Y2.

X3Y1's 9-bit address aliases a 64-entry x 32-word cache into 512 words.
This iteration uses four genuine 512x64 SRAM macros and an 11-bit address.
The synchronous read bank select is registered. Operand staging registers are
explicit 4-bit declarations rather than implicit 1-bit signals.

This does NOT establish full inference correctness. Known blockers include
MLA query has only 32 elements but attention indexes 128, MLA projection uses
64 output limit, token low nibbles are zero, final SRAM write enable is dropped,
attention reads uninitialized entries, persistent accumulator and depleted
weight shift registers, placeholder state/convolution/normalization/output.
Do not call PPA results a verified inference implementation.

X3Y3 large adds executable unsigned INT4 MAC reference and full-top protocol
tests. Fixes completion pulse, seq_start count reset and last SRAM append
write timing. These tests do not validate inference. MAC arithmetic reference
is expected to expose signedness errors in the inherited implementation.
