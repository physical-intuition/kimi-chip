# X3-Y2 Design Notes

X3-Y2 strengthens the regression oracle with alternating signed INT4 extrema, `-8` and `+7`, across every row, column, and K lane. Its SHA-256-locked K=7, K=0, and K=13 back-to-back regression passed all 768 outputs, and the external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume gates passed.

The real full Nangate45 ORFS flow completed with `FLOW_RC=0`. Final extracted STA is clean at 468.201 MHz estimated fmax, with 0.364167 ns setup worst slack, 0.00331735 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 29,754 initial violations to zero in five repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577.128 um² and 134,135 standard cells. The final route has 135,481 non-filler cells, 170,536 um² design area, 376,508 total instances including 241,027 fillers and 3,620 tap cells, and 20.1407% utilization in an 846,722 um² core. Detailed routing took 2,753.16 seconds, peaked at 4,920.2421875 MB, and used 3,276,361 um of wire and 955,757 vias. Total power is 225.265 mW; worst VDD and VSS drops are 4.94346 mV and 3.83038 mV.

The signed-extrema oracle did not disturb the physical implementation, as expected for a regression-only X3 iteration. It closes one functional-test gap but still permits a row, column, or output-address permutation to be masked by dense repeating patterns. X3-Y3 should lock a sparse lane-identity stimulus that makes every output coordinate independently recognizable.
