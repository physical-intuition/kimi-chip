# X3-Y4 Design Notes

X3-Y4 locks control-plane behavior that arithmetic-value tests do not cover. Its nonlinear signed K=7, K=0, and K=13 sequence asserts paired activation and weight requests, exactly one write to each of the 256 output addresses, latching of `k_dim` after launch, and immunity to a spurious `start` pulse while the core is busy. The SHA-256-locked regression passed all 768 unique outputs, and the external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume gates passed.

The real full Nangate45 ORFS flow completed through final extracted reporting and GDS generation. Final STA is clean at 468.201 MHz estimated fmax, with 0.364167 ns setup worst slack, 0.00331735 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 29,754 initial violations to zero in five repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577 um² and 134,135 standard cells. The final route has 135,481 non-filler cells, 170,536 um² design area, 376,508 total instances including 241,027 fillers and 3,620 tap cells, and 20.1407% utilization in an 846,722 um² core. Detailed routing took 2,751.67 seconds, peaked at 5,108.31 MB, and used 3,276,361 um of wire and 955,757 vias. Total power is 225.265 mW; worst VDD and VSS drops are 4.94346 mV and 3.83038 mV.

The launch wrapper wrote an empty `FLOW_RC` marker after the container exited. No return code was invented. Terminal success is instead backed by completion of the final GDS/report sequence, zero errors in `6_report.json`, and all strict report-backed checks. The malformed marker is preserved with the raw artifacts.

The control-plane oracle did not perturb the physical implementation. X3-Y5 should lock reset-abort and clean-restart behavior so an interrupted transaction cannot leak stale requests, writes, or accumulator state into a fresh required K=7/K=0/K=13 sequence.
