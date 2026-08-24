# X4-Y2: registered-boundary control-cone isolation at 760 MHz

Y1 final extraction showed that the hierarchical accumulator was not critical. Both setup failures ran from `issued[0]` through a 15-stage progress comparator and control cone to the paired request outputs. The `issued < k_dim_q` predicate is redundant because the controller enters `S_REQ` only after a nonterminal start or accumulation event.

Y2 removes that predicate so request assertion depends only on the registered FSM state. This preserves the request cycle, paired request semantics, addresses, arithmetic, and total operation latency while isolating the external request boundary from the 16-bit progress comparator. A new cumulative executable lint rule rejects reintroduction of progress-dependent request decode.

Y1s next clean weight-data-to-chunk path had about 30 ps slack at 752 MHz. With the existing 20% I/O budget, that implies about 774 MHz headroom. Y2 targets 760 MHz at 1.315789 ns, above 752 MHz but retaining margin for physical variation. Terminal evidence remains pending.

The real full Nangate45 flow completed with `FLOW_RC=0` and strict PASS. Final extraction achieved 783.569 MHz at the 760 MHz target, with +0.0395887 ns setup WNS, 0 setup TNS, +0.0388065 ns hold WNS, and zero setup, hold, slew, fanout, or max-capacitance violations. Detailed routing started with 30,300 violations and finished with zero DRC; antenna net and pin counts are both zero. The final design area is 202,006 um².

The new worst path starts at `drain_col[0]` and ends at `out_wdata[12]`, traversing the combined row/column accumulator readout selector in 18 combinational cells. Y3 must split that selector across registered stages before raising frequency.

The Y2 launch wrapper accidentally copied the Y1 artifact path after completion. An independent preservation process and a final direct copy from the still-live `x4_y2_kimi` ORFS tree recovered the correct raw Y2 evidence. Y3's wrapper must use its own design path.
