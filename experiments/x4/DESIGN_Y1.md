# X4-Y1: 752 MHz hierarchical-fold baseline

X4-Y1 replaced the wide per-cycle accumulator with a signed 12-bit chunk accumulator and signed 24-bit wide state. It folds every 16 valid products on a separate multiplier-free cycle, flushes the tail before drain, consumes each paired registered-SRAM response exactly once, and preserves the stationary indexed output drain. The 16-bit `k_dim` interface supports K through 65,535.

The local functional regression passed K=7/0/13, K=15/16/17/31/32/33, signed extrema, busy-start and latched `k_dim`, reset abort and clean restart, request pairing, tail flush, and adversarial K=65,535. All eleven executable structural and width-proof checks passed.

The full Nangate45 flow completed with `FLOW_RC=0`. Detailed routing reduced 28,913 initial violations to zero in four repair iterations; final DRC, antenna, hold, max-slew, max-fanout, and max-capacitance checks are clean. Final routed area is 196,320 um² across 149,585 non-filler cells. Routing uses 3,436,326 um of wire and 985,696 vias.

The cell is a strict FAIL because it missed the 752 MHz setup target. Extracted fmax is 719.14 MHz, WNS is -0.06075 ns, TNS is -0.121209 ns, and two request-output endpoints violate. The worst path runs from `issued[0]` through a 15-stage comparator/control cone to `weight_req`; the same structure drives `act_req`. The datapath is not the limiting path.

Y2 removes the redundant `issued < k_dim_q` predicate from request generation. The state machine already enters `S_REQ` only for a valid unconsumed element, so this preserves request timing and external behavior while eliminating the progress comparator from the output cone. The next reported weight-data-to-chunk path has about 30 ps slack at 752 MHz, corresponding to roughly 774 MHz under the same 20% I/O budget. Y2 therefore targets 760 MHz, monotonically above 752 MHz with margin rather than guessing at a distant ladder point.
