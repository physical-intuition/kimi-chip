# X2-Y4 Design Notes

X2-Y4 preserves the linted indexed-readout datapath and refines the capacitance-repair boundary with `CAP_MARGIN=22`. Its K=7, K=0, and K=13 back-to-back regression passed all 768 outputs, and the external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume gates all passed.

The full Nangate45 ORFS flow completed with `FLOW_RC=0`. Final extracted STA is clean at 470.547 MHz estimated fmax, with 0.374812 ns setup worst slack, 0.00309652 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 30,724 initial violations to zero in four repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577.128 um² and 134,135 standard cells. The final route has 135,538 non-filler cells, 170,601 um² design area, 376,923 total instances including 241,385 fillers and 3,620 tap cells, and 20.1485% utilization in an 846,722 um² core. Detailed routing took 2,755.23 seconds, peaked at 5,072.26 MB, and used 3,273,509 um of wire and 958,420 vias. Total power is 225.562 mW; worst VDD and VSS drops are 5.14391 mV and 3.75619 mV.

Compared with `CAP_MARGIN=25`, margin 22 improves extracted fmax by 2.201 MHz and removes 221 um² of routed area while retaining strict closure. The observed closure boundary is now between Y1's failing margin 20 and Y4's passing margin 22. Y5 tests `CAP_MARGIN=21` as the final X2 boundary refinement.
