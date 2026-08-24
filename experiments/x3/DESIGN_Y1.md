# X3-Y1 Design Notes

X3-Y1 establishes the regression-locked baseline on X2's minimum tested clean physical point. It adds a SHA-256-locked deterministic K=7, K=0, and K=13 back-to-back testbench, preserves the failed-directions memory, and retains all three executable X2 policy gates. The locked regression passed all 768 outputs and the SRAM-boundary, accumulator-range, and one-response/one-consume gates passed.

The real full Nangate45 ORFS flow completed with `FLOW_RC=0`. Final extracted STA is clean at 468.201 MHz estimated fmax, with 0.364167 ns setup worst slack, 0.00331735 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 29,754 initial violations to zero in five repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577 um² and 134,135 standard cells. The final route has 135,481 non-filler cells, 170,536 um² design area, 376,508 total instances including 241,027 fillers and 3,620 tap cells, and 20.1407% utilization in an 846,722 um² core. Detailed routing took 2,666.81 seconds, peaked at 4,925.58 MB, and used 3,276,361 um of wire and 955,757 vias. Total power is 225.265 mW; worst VDD and VSS drops are 4.94346 mV and 3.83038 mV.

The physical metrics match the underlying X2-Y5 datapath, as expected, while X3-Y1 makes the functional oracle and failed-direction history durable experimental inputs. X3-Y2 should strengthen the locked oracle with an independent signed-extrema stimulus pattern while preserving the required K=7/0/13 sequence and rerunning the full physical flow.
