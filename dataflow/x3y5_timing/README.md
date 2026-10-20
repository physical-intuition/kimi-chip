# X3Y5 routed experiment, timing NOT closed

Identical RTL and debug latency to X3Y4. Clock 0.6 ns and I/O delays
0.1 ns unchanged; no new false paths. The inherited reset exception is unchanged.
Post-CTS OpenDB swapMaster upsized 39 debug output flops to DFFR_X2.
The original resize_cell hook failed; this repaired hook executed successfully.
Setup repair margin 0.03 ns; post-global-route WNS repair enabled.

Final routed flow exited 0. Reports in reports_final and metrics_final.json.
Setup WNS -0.0370313 ns, TNS -1.59957 ns, 72 violating endpoints.
Fmax 1.56978 GHz. This REGRESSES X3Y4 (-0.0245119 ns, 39 endpoints,
1.60125 GHz). Do not use this experiment as a closed-timing implementation.
Worst path is argmax_reg[4] to argmax_id[4], not a debug hash.
Clock insertion about 0.34 ns, clock-to-Q about 0.15 ns, followed by
output buffer; arrival about 0.54 ns versus 0.50 ns required.
Next targeted work must address constrained output clock insertion/loading,
including argmax, rather than assuming debug-only resizing closes timing.

Hold slack +0.0302688 ns, zero hold violations.
Zero slew/fanout violations; ONE capacitance violation remains.
Geometric route DRC report is empty (zero violations).
Non-filler area 407942 um2 (338736 standard cells + 69205.8 macros).
Vectorless estimated power 1.05374 W. JSON also contains an earlier
filler-inclusive duplicate area key; non-filler area is reported here.

All six regression suites passed after report collection, including
393580-cycle protocol, MAC reference, exhaustive/random MAC pipeline,
debug latency/reset, weight equivalence, and bank addressing.
Full inference remains unverified; see inherited CORRECTNESS.md blockers.
