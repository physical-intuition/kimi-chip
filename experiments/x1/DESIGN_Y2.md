# X1-Y2 Design Notes

Y2 keeps the same functional contract as Y1: one signed INT4 16x16 outer product per accepted activation/weight word, 24-bit accumulators, one-cycle external SRAM reads, and a serialized 24-bit output interface.

The physical change is the drain topology. Y1's flat 256-entry shift drain moved every accumulator on every output cycle, creating a global 6144-bit register-to-register network that global routing could not converge. Y2 partitions the accumulator state into sixteen row-local banks of sixteen 24-bit words. During drain, only the selected row bank shifts. A fixed 16:1 mux selects the head of the active bank. This preserves row-major output ordering while reducing each shift network from 256 words to 16 words and avoiding a flat 256:1 output mux.

The testbench runs three operations back-to-back, including K=7, K=0, and K=13, and checks all 768 output writes. This also verifies accumulator clearing and controller reuse.

Physical implementation uses a 5 ns clock constraint and a deliberately loose 20% initial core utilization. Y1 established that pre-route timing was already adequate and routing topology was the limiting factor, so Y2 prioritizes completing detailed routing before recovering area.

As in Y1, activation, weight, and output SRAMs remain external interfaces. Reported physical area therefore covers the compute and controller standard cells but excludes the 96 KiB of SRAM macros.

Y2 completed the full Nangate45 route. Global-route timing met the 5 ns constraint with 2.36 ns worst slack and an estimated 378.63 MHz maximum frequency. Detailed routing repaired the violation count from 14,915 in the initial pass to 0, with 0 antenna net and pin violations. The routed design area is 169,999 um² at 20% utilization, inside an 849,995 um² core. Detailed routing took 2,605 seconds and peaked at 4,824.67 MB.

The result confirms that drain locality, rather than MAC timing, was Y1's dominant failure. Y3 should retain row-local state but remove even the selected-bank shift. A per-bank read pointer or hierarchical non-shifting read mux would avoid rewriting 384 bits on every drain cycle. Y3 should also add an explicit post-route STA target; Y2's timing result comes from global-route extraction because the resumed route-only flow generated the final routed database and DRC report without a separate post-route timing stage.
