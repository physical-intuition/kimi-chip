# X7: KDA Dataflow Chip - Production Architecture

## Goal
Complete KDA inference chip that synthesizes to timing closure at 500+ MHz on Nangate45.

## Critical Fixes from X6

### 1. SRAM Macro Inference
X6 failed because Yosys expanded `reg [N:0] mem [0:M]` to flip-flops + mux trees.

**Fix:** Use `fakeram45_512x64` behavioral macros explicitly:
- Weight SRAM: 16 macros total (4 per K/V/Q/O matrix)
  - Each matrix: 128×128 = 16KB = 4 × fakeram45_512x64
  - 4 macros read in parallel = 256 bits/cycle = 32 INT8/cycle
- State SRAM: 8 macros total (4 per ping-pong bank)
  - Each bank: 128×128 = 16KB = 4 × fakeram45_512x64
  - 4 macros read/write in parallel = 32 INT8/cycle
- Activation buffer: 4 macros (2 per I/O buffer)

Macro interface:
```verilog
module fakeram45_512x64 (
  input clk,
  input ce_in,      // chip enable
  input we_in,      // write enable
  input [8:0] addr_in,
  input [63:0] wd_in,
  output reg [63:0] rd_out
);
```

### 2. Iterative RMSNorm Pipeline
X6 Y5 had 109K-gate combinational norm_unit that killed ABC.

**Fix:** 4-stage pipelined iterative RMSNorm:
- Stage 1: Accumulate x² over 128 elements (8 cycles, 16 elements/cycle)
- Stage 2: Compute mean = sum/128 (shift by 7)
- Stage 3: Newton-Raphson reciprocal sqrt (3 iterations, 6 cycles)
- Stage 4: Scale outputs x * rsqrt(mean + eps) (8 cycles, 16 elements/cycle)

Total: ~24 cycles for RMSNorm vs combinational explosion.

### 3. Serialized MAC Architecture (from X6 Y5)
- Single 16×16 MAC array, time-multiplexed across K/V/Q/O projections
- 128 output lanes processed in 8 chunks of 16
- Each projection: 128 × 128 × 8 cycles = 8192 MACs over 512 cycles

### 4. Memory Bandwidth Budget
Per cycle at 500 MHz:
- Weight read: 64 bits = 8 INT8 weights
- Activation read: 64 bits = 8 INT8 activations  
- Result write: 64 bits = 8 INT8 outputs

Schedule (cycles):
```
K_PROJ:     512  (128×128 matmul, 16 outputs/8 cycles)
V_PROJ:     512
Q_PROJ:     512
CONV:       32   (4-tap conv on 128 channels, 4 cycles/channel chunk)
STATE_P1:   128  (S' = diag(α) · S, serialized)
STATE_D:    128  (d = β·k·(v - k·S'), serialized) 
STATE_P2:   128  (S = S' + d, serialized)
O_PROJ:     512  (output from state)
NORM:       24   (iterative RMSNorm)
RESIDUAL:   8    (add skip connection)
TOTAL:      2496 cycles/token
```

## RTL Module List

1. `fakeram45_512x64.v` - SRAM behavioral macro
2. `weight_sram.v` - 6-bank weight memory with striped addressing
3. `state_sram.v` - ping-pong state memory
4. `activation_sram.v` - double-buffered activation memory
5. `mac_array_16x16.v` - signed INT8 MAC with INT24 accumulator
6. `requant.v` - INT24→INT8 with arithmetic shift + saturate
7. `conv_unit.v` - 4-tap 1D convolution for α/β gates
8. `state_update.v` - serialized KDA state recurrence
9. `norm_unit.v` - iterative RMSNorm pipeline
10. `residual_unit.v` - skip connection adder
11. `x7_controller.v` - FSM orchestrating all phases
12. `x7_top.v` - top-level integration

## Verification Checklist
- [ ] Each module passes standalone testbench
- [ ] Weight SRAM reads all 6 banks correctly
- [ ] State SRAM ping-pong works
- [ ] MAC produces correct INT24 accumulation
- [ ] Requant saturates at boundaries
- [ ] Conv computes correct α/β gates
- [ ] State update matches golden (Python reference)
- [ ] Norm produces correct scaled outputs
- [ ] End-to-end test: output depends on input through all stages
- [ ] Full Yosys+ABC synthesis completes
- [ ] Timing closes at 500 MHz (2.0 ns)

## Synthesis Flow
```tcl
# flow/synth_x7.ys
read_verilog rtl/*.v
hierarchy -top x7_top
proc; opt; memory -nomap  # keep SRAMs as macros
techmap; opt
dfflibmap -liberty $NANGATE45_LIB
abc -liberty $NANGATE45_LIB -D 2000  # 2.0ns = 500MHz
stat
write_verilog artifacts/x7_mapped.v
```

## Success Criteria
1. All RTL tests pass
2. Synthesis completes without OOM
3. ABC reports delay ≤ 2.0 ns
4. No DRC violations in mapped netlist
