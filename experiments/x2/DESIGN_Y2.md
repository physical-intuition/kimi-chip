# X2-Y2 Design Notes

X2-Y2 preserves X2-Y1's indexed-readout datapath and all three executable X2 gates, then raises `CAP_MARGIN` from 20 to 30 after Y1 retained one final extracted max-capacitance violation. The local K=7, K=0, and K=13 back-to-back regression passed all 768 outputs. The external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume control gates all passed.

The full Nangate45 ORFS flow completed with `FLOW_RC=0`. Final extracted STA is clean at 467.594 MHz estimated fmax, with 0.361391 ns setup worst slack, 0.00316602 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 30,927 initial violations to zero in five repair iterations. Final DRC is zero, and antenna analysis reports zero violating nets and pins.

Synthesis reports 169,577.128 um² and 134,135 standard cells. The final route has 136,044 non-filler standard cells, 171,307 um² design area, and 377,558 total instances including 241,514 fillers and 3,620 tap cells inside an 846,722 um² core at 20.2318% utilization. Detailed routing took 2,669 seconds, peaked at 4,861 MB, and used 3,273,436 um of wire and 960,617 vias. The complete remote flow took 4,843 seconds. Power analysis estimates 226.021 mW total power, with 4.95219 mV worst VDD drop and 3.6838 mV worst VSS drop.

The stronger margin fixes Y1's only signoff defect, but compared with `CAP_MARGIN=20` it increases final routed area by 0.49% and reduces extracted fmax by 0.46%. Y3 should bisect the successful interval with `CAP_MARGIN=25`, preserving all executable lint rules and the exact functional contract, to test whether clean extraction can be retained with less overhead.
