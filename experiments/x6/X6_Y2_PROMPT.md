# X6-Y2: Block RTL Generation

## Goal
Generate synthesizable Verilog for all major blocks in the X6 KDA dataflow chip, based on the architecture defined in Y1.

## Required Reading
1. `/home/kit/kimi-chip/experiments/x6/X6_SPEC.md` - overall chip spec
2. `/home/kit/kimi-chip/experiments/x6/architecture.json` - Y1 architecture decisions
3. `/home/kit/kimi-chip/experiments/x6/architecture_rationale.md` - cycle budget derivations

## Blocks to Implement

### 1. MAC Array (16×16)
- File: `/home/kit/kimi-chip/experiments/x6/rtl/mac_array_16x16.v`
- INT4 weights × INT8 activations → INT24 accumulators
- Weight stationary dataflow
- Local 2048-bit weight buffer
- 256 MACs per cycle
- Reference X4/X5 MAC designs in `/home/kit/kimi-chip/experiments/x4/` and `/home/kit/kimi-chip/experiments/x5/`

### 2. State Update Datapath
- File: `/home/kit/kimi-chip/experiments/x6/rtl/state_update.v`
- 128-lane parallel datapath
- Pass 1: A[i,j] = alpha[i] * S[i,j], accumulate u[j] += k[i] * A[i,j]
- Pass 2: S_new[i,j] = A[i,j] + k[i] * d[j], accumulate q_out[j] += q[i] * S_new[i,j]
- INT24 precision throughout
- 3072-bit state row interface (128 × 24 bits)

### 3. Conv Unit (α/β gates)
- File: `/home/kit/kimi-chip/experiments/x6/rtl/conv_unit.v`
- 16-lane depthwise convolution
- Kernel size 4, 128 channels
- INT8 × INT4 → INT8 output
- PWL sigmoid/tanh approximation (2-cycle pipeline)
- Produces both alpha and beta in parallel

### 4. Norm Unit (RMSNorm)
- File: `/home/kit/kimi-chip/experiments/x6/rtl/norm_unit.v`
- 16-lane normalization
- INT24 input, INT8 output
- 24 cycles for 128 elements

### 5. Residual Unit
- File: `/home/kit/kimi-chip/experiments/x6/rtl/residual_unit.v`
- Skip connection add
- 8 cycles for 128 elements

### 6. Weight Crossbar (6→2)
- File: `/home/kit/kimi-chip/experiments/x6/rtl/weight_crossbar.v`
- 6 input ports (256-bit each from weight banks)
- 2 output ports (2048-bit each to MAC array buffers)
- Configurable routing

### 7. Activation Crossbar
- File: `/home/kit/kimi-chip/experiments/x6/rtl/activation_crossbar.v`
- Routes activations between MAC outputs, state datapath, conv, norm, residual
- 256-bit external interface

## Design Constraints
- Target: 500 MHz on Nangate45
- Use behavioral SRAM models for now (will swap to hard macros in Y4)
- Keep critical paths short - use registered outputs
- Include basic assertions for protocol checking

## Output Requirements
1. All RTL files listed above
2. `/home/kit/kimi-chip/experiments/x6/rtl/x6_top.v` - top-level integration stub (ports only, no logic)
3. `/home/kit/kimi-chip/experiments/x6/Y2_SUMMARY.md` - what was built, any design decisions, known limitations

## What NOT to do
- Do not write testbenches (Y3)
- Do not run synthesis (Y4)
- Do not commit or push
