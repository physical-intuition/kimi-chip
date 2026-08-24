# X1-Y3 Design Notes

Y3 is a timing-focused refinement of Y2. It preserves Y2's routable topology of sixteen row-local accumulator banks, while latching `k_dim` at operation start and removing asynchronous reset from the 6,144 accumulator bits. The testbench changes external `k_dim` immediately after launch and verifies K=7, K=0, and K=13 back-to-back, with all 768 outputs correct.

Physical implementation uses Nangate45 at a 2.5 ns clock constraint, or 400 MHz, with 20% core utilization. The full flow ran on the 16 GiB GCS Intel VM with four routing threads. Activation, weight, and output SRAMs remain external, so the area excludes the 96 KiB SRAM macros.

Y3 completed the full flow successfully. Final extracted timing reports 0.342 ns setup slack, 0.00094 ns hold slack, zero setup and hold violations, and a 463.49 MHz estimated fmax. This clears the 400 MHz target by 15.9%. Detailed routing converged from 30,998 initial violations to zero after four repair iterations, with zero antenna net and pin violations. The final route uses 3,094,981 um of wire and 999,608 vias.

Synthesis produced 138,720 standard cells occupying 173,877.55 um². The final routed design contains 138,733 non-filler standard cells occupying 174,403 um² inside an 867,822 um² core at 20.10% utilization. The complete final instance count is 383,900 when 245,167 filler cells and 3,664 tap cells are included.

Detailed routing took 2,798 seconds and peaked at 5,013.72 MB. Total wall time from Y3 launch through final GDS completion was 5,203 seconds, or 1 hour 26 minutes 43 seconds. Final power analysis estimates 261.65 mW total power, with worst IR drop of 4.59 mV on VDD and 6.09 mV on VSS.

Compared with Y2, final fmax improved from 378.63 MHz to 463.49 MHz, a 22.4% gain. Synthesized area increased only 0.20%, while final routed area increased 2.59% and non-filler cell count increased 2.56%. Routing used 11.85% more wire, 3.89% more vias, 3.92% more peak memory, and 7.42% more detailed-route time. Despite the tighter timing target, total wall time fell 37.7% because Y3 ran as one uninterrupted full flow.

One electrical-cleanliness issue remains: final STA reports 16 maximum-capacitance violations, despite zero setup, hold, slew, fanout, DRC, and antenna violations. Y3 is a pass under the experiment's stated functional, timing, DRC, and antenna criteria, but Y4 should repair those capacitance violations before claiming a fully signoff-clean design. The reset removal did not shrink synthesis area as expected; timing closure inserted enough additional buffering that routed area grew slightly. Y4 should target capacitance repair and then test a non-shifting bank readout rather than assuming reset removal is an area win.