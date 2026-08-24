# X5-Y4

X5-Y4 starts only from X5-Y3's terminal routed result. Y3 passed its 930.359 MHz target with +0.0633 ns setup slack, zero setup/hold violations, clean DRC/antenna/cap checks, and an extracted Fmax of 988.581 MHz.

The final critical path was not arithmetic. It ran from `state[1]` through state decode and output buffering to `busy`. Y4 registers `busy` as protocol state, setting it on accepted start and clearing it with final completion. The next measured internal setup path was `product_pipe[140][3]` to `chunk_accum[140][11]`, with +0.14 ns slack at Y3's 1.074853466 ns constraint. That implies an approximate internal ceiling of 1069.686 MHz.

The target is derived as `min(1000, 988.581 + 0.5 * (1069.686 - 988.581))`. The unclamped result is 1029.134 MHz, so Y4 uses a progressive 1.000 ns, 1 GHz target rather than jumping above the requested milestone.

Y4 preserves Y3's registered request outputs, 5-bit burst budget, registered 8-bit product and MAC-commit pipeline, 6/6/12 fold, and CAP_MARGIN 50. Full inherited functional regression through K=65,535 and structural/tool checks pass. Y5 remains unplanned.
