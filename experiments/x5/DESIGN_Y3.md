# X5-Y3

X5-Y3 is derived from X5-Y2 terminal routing evidence and the historical X4-Y1 to X4-Y2 request-comparator repair. Y2's MAC pipeline removed the original `act_rdata` to `chunk_accum` setup cone, but its overlapped combinational request predicate created a new `issued[10]` to `act_req` worst path. Y2 completed at 890.470 MHz with -0.06 ns WNS, -0.111804 ns TNS, two setup violations, and two max-cap failures.

Y3 preserves the registered 8-bit product and overlapped request, product-capture, and MAC-commit pipeline. Request outputs now come directly from `request_active` and `request_addr` registers. A 5-bit `requests_left` budget controls each at-most-16-element burst, so no `issued < k_dim_q` or chunk-limit comparator remains on external request outputs. The inherited 6/6/12 fold remains unchanged.

The target is evidence-derived rather than chosen directly. Removing the same request comparator in X4 improved extracted Fmax by 8.959%. Y3 conservatively applies half that observed recovery to Y2's 890.470 MHz, deriving 930.359 MHz and a 1.074853466 ns period. CAP_MARGIN rises from 30 to 50 because Y2's final report showed two max-cap violations, including 357.07 versus a 242.31 limit.

The inherited functional suite passes through K=65,535, including fold boundaries, signed extrema, busy-start rejection, reset-abort/restart, and exactly-once output. X5-Y4 and X5-Y5 remain unplanned.
