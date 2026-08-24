# X3 Failed-Directions Memory

This file is part of the X3 experiment contract. New cells must consult it before proposing a change, and terminal failures should be added with report-backed evidence.

## Global 256-word shift drain

X1-Y1 used a monolithic 256-word shift-drain network. It failed to converge in global routing. Do not retry a global shift chain without a structural locality change.

## Unmargined extracted capacitance closure

X1-Y3 and X2-Y1 showed that a flow can finish with clean timing, DRC, and antenna checks while still failing strict signoff on extracted maximum capacitance. X2-Y1 at `CAP_MARGIN=20` retained one max-capacitance violation. Do not treat `FLOW_RC=0` as signoff by itself.

## Excessively conservative capacitance repair

X2-Y2 at `CAP_MARGIN=30` closed cleanly, but X2-Y3 and X2-Y4 demonstrated that lower margins improved area and fmax while retaining closure. Do not default to margin 30 when a report-backed lower clean boundary exists.

## Behavioral SRAM inference

A Verilog array such as `reg [63:0] mem [0:511]` maps to registers and muxes in this flow, not a physical SRAM macro. Keep storage at an explicit external macro boundary unless a real platform macro is instantiated and included in area and timing evidence.
