# X5-Y2

X5-Y2 responds only to X5-Y1's terminal routed evidence. X5-Y1 completed with `FLOW_RC=0` but missed 937.092 MHz with setup WNS -0.03 ns, TNS -0.0754784 ns, five setup violations, and extracted fmax 911.455 MHz. Its worst path moved from the repaired fold cone to `act_rdata[28]` through the signed multiply and accumulator logic to `chunk_accum[121][11]`.

Y2 holds the target at 937.092 MHz instead of moving the goalpost. Each 4x4 signed product is captured in an 8-bit `product_pipe`, then committed to the 12-bit chunk accumulator one stage later. `response_valid` and `product_valid` track the synchronous memory response and registered product. Requests, product captures, and MAC commits overlap in `S_RUN`; the old alternating `S_REQ` and `S_ACCUM` states are gone. A 16-request chunk boundary provides backpressure while the two-stage pipeline drains before the inherited three-stage fold.

The inherited regression covers K=0, fold boundaries, signed extrema, reset-abort/restart, busy-start rejection, exactly-once output, and K=65,535. Structural checks require the registered 8-bit product, overlapping valid pipeline, signed extension, chunk backpressure, inherited fold, fixed target, and absence of any Y3 pre-plan.
