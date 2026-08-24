# X3-Y5 Design Notes

X3-Y5 locks mid-run asynchronous-reset abort, post-abort quiescence, and clean restart behavior. Its SHA-256-locked regression aborts an active transaction, asserts no stale requests or writes after reset, and then runs K=7, K=0, and K=13 back-to-back. All 768 post-restart outputs passed. The external SRAM-boundary, 24-bit accumulator-range, and one-response/one-consume executable gates also passed.

The first remote attempt reached zero detailed-route and antenna violations but failed while writing `5_2_route.odb` because the GCS root filesystem was full. That infrastructure failure and its `FLOW_RC=2` are preserved separately under `artifacts/y5_failed_disk_full`. After removing only historical generated checkpoints whose evidence had already been preserved, the same cell was retried from scratch.

The retry completed the real full Nangate45 ORFS flow with `FLOW_RC=0`. Final STA is clean at 468.201 MHz estimated fmax, with 0.364167 ns setup worst slack, 0.00331735 ns hold worst slack, zero setup and hold TNS, and zero setup, hold, max-slew, max-fanout, and max-capacitance violations. Detailed routing reduced 29,754 initial violations to zero in five repair iterations. Final DRC and antenna counts are zero.

Synthesis reports 169,577 um² and 134,135 standard cells. The final route has 135,481 non-filler cells, 170,536 um² design area, 376,508 total instances including 241,027 fillers and 3,620 tap cells, and 20.1407% utilization in an 846,722 um² core. Detailed routing took 2,759.11 seconds, peaked at 4,983.92 MB, and used 3,276,361 um of wire and 955,757 vias. Total power is 225.265 mW; worst VDD and VSS drops are 4.94346 mV and 3.83038 mV.

X3 is complete. X4 must now ingest every X1-X3 success and failure into machine-readable patterns and executable evidence-backed lint rules before implementing its 752 MHz hierarchical-fold Y1 baseline.
