# flow/ - exact ORFS configs behind every reported number

Drop any of these under OpenROAD-flow-scripts/flow/designs/nangate45/ and run
`make DESIGN_CONFIG=designs/nangate45/<name>/config.mk` (frozen 26Q2 image).
RTL sources go in designs/src/<name>/ per each config's VERILOG_FILES glob
(all RTL is in this repo's rtl/).

- kimi_v4_p{133,110,090}   - v4 unmodified, constraint sweep (752/909/1111 MHz targets)
- kimi_v9_p*               - v9 sweep (same targets)
- kimi_v10a_p{090,075,066} - v10a sweep (1111/1333/1515 MHz targets)
- kimi_v10b_p*             - v10b (CSA) sweep
- kimi_fullchip            - full chip @ 1.33 ns: 16x fakeram45_512x64 platform macros
- kimi_fullchip_p120       - same design @ 1.20 ns (ceiling probe)
- kimi_ctrlarm             - unmodified inference_accelerator (memories as flops) - the baseline arm

All SDCs: single clock, 20%-of-period I/O delays, 0.1 ns clock uncertainty,
set_false_path on the async rst_n. Timing-repair skips appear only on
kimi_ctrlarm (its flop-memory WNS is structurally huge; bounding repair keeps
the run finite - same posture as large-core ORFS configs upstream).
