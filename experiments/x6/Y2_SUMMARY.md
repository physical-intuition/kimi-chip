# X6-Y2 RTL Summary

Y2 adds synthesizable block-level RTL for the one-head X6 KDA architecture. It does not add testbenches, synthesis scripts, SRAM macros, or a connected top-level scheduler.

## Files

- `rtl/mac_array_16x16.v`: 256 INT4xINT8 multipliers arranged as sixteen 16-term dot products, INT24 accumulation, registered multiply reduction, and two 2048-bit local weight buffers.
- `rtl/state_update.v`: 128-lane, two-pass state datapath over a 3072-bit row. Pass 1 produces `A=diag(alpha)S` and `u=k^T A`; pass 2 produces `S_new=A+k d^T` and the fused query reduction.
- `rtl/conv_unit.v`: sixteen parallel four-tap depthwise alpha and beta convolutions with registered PWL sigmoid and tanh outputs.
- `rtl/norm_unit.v`: sixteen-lane, 24-cycle collection/refinement/emission RMSNorm structure with an initial power-of-two reciprocal-square-root approximation.
- `rtl/residual_unit.v`: sixteen-lane signed saturating residual add, completing 128 values in eight accepted beats.
- `rtl/weight_crossbar.v`: registered routing from six 256-bit banks into two independently assembled 2048-bit local lines.
- `rtl/activation_crossbar.v`: registered three-source/four-destination 256-bit activation routing.
- `rtl/x6_top.v`: integration boundary and ports-only stub with safe constant outputs.

## Interface decisions

Wide vectors use lane 0 in the least-significant slice. Signed INT8, INT4, and INT24 values use two's complement. State alpha, k, q, and delta multiplications use a Q1.7-style right shift of seven bits. State reductions saturate to INT24 at every row, as required by the Y1 decision to keep persistent arithmetic at INT24.

The state unit exposes one generic `reduction_vector`. After pass 1 it is `u`; after pass 2 it is the fused query output. A controller must capture it when `done` asserts and supply the precomputed `d=beta(v-u)` vector for pass 2.

All active datapath outputs are registered. Assertions are guarded by `ifndef SYNTHESIS` and check starts while busy, invalid routing selections, incomplete weight activation, and inputs presented outside accepted protocol phases.

## Known limitations for Y3/Y4

The top-level scheduler and behavioral state/weight SRAM arrays are not instantiated yet; Y2 models local MAC weight storage behaviorally and exposes external SRAM interfaces at the chip boundary.

The RMSNorm reciprocal-square-root stage currently uses a coarse power-of-two seed and reserves eight registered refinement cycles without a full Newton update. This is structurally timed at 24 cycles but not yet numerically production-accurate. Y3 should compare it against the fixed-point golden model and replace the seed-only behavior with a small characterized LUT plus fixed-point Newton step.

The MAC accumulation path computes one registered sixteen-product lane sum followed by INT24 accumulation. It does not reuse X5's 12-to-24-bit hierarchical fold because each accepted X6 beat already reduces exactly sixteen products before entering the persistent accumulator. Y4 timing reports must determine whether the combinational sixteen-product reduction needs an adder tree split.

PWL sigmoid and tanh thresholds are provisional fixed-point choices. Y3 must lock their input scaling against the KDA software reference.

No claim is made that 500 MHz closes before Y4 synthesis and timing analysis. The RTL is organized around registered interfaces and short state boundaries so timing-driven changes can be localized.
