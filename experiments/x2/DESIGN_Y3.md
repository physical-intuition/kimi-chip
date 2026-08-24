# X2-Y3 Design Notes

X2-Y3 preserves the linted indexed-readout datapath and bisects the observed capacitance-repair interval with `CAP_MARGIN=25`. Its K=7, K=0, and K=13 back-to-back regression passed all 768 outputs, and the external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume gates all passed.

The full Nangate45 ORFS flow completed with `FLOW_RC=0`. Final extracted STA is clean at 468.346 MHz estimated fmax, with 0.364824 ns setup worst slack, 0.0037339 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 31,074 initial violations to zero in four repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577.128 um² and 134,135 standard cells. The final route has 135,691 non-filler cells, 170,822 um² design area, 376,477 total instances including 240,786 fillers and 3,620 tap cells, and 20.1745% utilization in an 846,722 um² core. Detailed routing took 2,793.55 seconds, peaked at 4,888 MB, and used 3,274,400 um of wire and 959,617 vias. Total power is 225.595 mW; worst VDD and VSS drops are 5.0806 mV and 3.80582 mV.

Compared with `CAP_MARGIN=30`, margin 25 improves extracted fmax by 0.752 MHz and removes 485 um² of routed area while retaining strict closure. Y4 tests `CAP_MARGIN=22`, refining the minimum clean margin between Y1's failing 20 and Y3's passing 25.
