# X2-Y5 Design Notes

X2-Y5 preserves the linted indexed-readout datapath and tests the final integer capacitance-repair boundary at `CAP_MARGIN=21`. Its K=7, K=0, and K=13 back-to-back regression passed all 768 outputs, and the external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume gates all passed.

The full Nangate45 ORFS flow completed with `FLOW_RC=0`. Final extracted STA is clean at 468.201 MHz estimated fmax, with 0.364167 ns setup worst slack, 0.00331735 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 29,754 initial violations to zero in five repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577.128 um² and 134,135 standard cells. The final route has 135,481 non-filler cells, 170,536 um² design area, 376,508 total instances including 241,027 fillers and 3,620 tap cells, and 20.1407% utilization in an 846,722 um² core. Detailed routing took 2,752.57 seconds, peaked at 4,901.50390625 MB, and used 3,276,361 um of wire and 955,757 vias. Total power is 225.265 mW; worst VDD and VSS drops are 4.94346 mV and 3.83038 mV.

Margin 21 is the minimum tested integer margin that closes every strict extracted criterion. It removes 65 um² relative to margin 22, but loses 2.346 MHz, so X2-Y4 remains the highest-fmax X2 point while X2-Y5 establishes the lower clean repair boundary. X3 begins from this clean boundary and adds a locked regression oracle plus failed-directions memory before further RTL changes.
