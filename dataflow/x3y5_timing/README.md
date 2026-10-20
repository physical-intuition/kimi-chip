# X3Y5 debug output timing closure

Based on X3Y4 with identical RTL, clock period (0.6 ns), I/O delays (0.1 ns),
reset false path, and debug sampling latency. Baseline routed WNS is
-0.0245119 ns with 39 violating endpoints, mostly debug output launch paths.

The worst debug driver was DFFR_X1 driving 24.88 fF, with 0.15 ns clock-to-Q.
A post-CTS hook upsizes debug output drivers to DFFR_X2 and relegalizes.
Timing repair targets 30 ps setup margin and post-global-route WNS repair is
enabled. These are physical implementation changes, not timing exceptions.

Baseline report and metrics are in baseline_reports. Final routed results
are pending. Run bash tests/run.sh for the six unchanged regression suites.
Full inference remains unverified; see inherited CORRECTNESS.md blockers.
