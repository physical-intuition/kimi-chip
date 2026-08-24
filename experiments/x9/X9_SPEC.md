# X9: KDA Dataflow Chip - Complete Numerical Specification

## X8 Achievements
- 12-macro weight SRAM (48KB) ✓
- 24-macro ping-pong state SRAM (96KB) ✓
- 644-cycle legal schedule ✓
- O after STATE_P2 ✓
- Controller synthesis: 470ps delay, 489µm²

## X9 Additions: Numerical Contracts

### 1. Precision Format

| Tensor | Format | Range | Notes |
|--------|--------|-------|-------|
| Weights (W_k, W_v, W_q, W_o) | INT4 signed | [-8, 7] | Stored in SRAM |
| Activations (x) | INT8 signed | [-128, 127] | Input to projections |
| Projection accumulators | INT24 signed | [-2^23, 2^23-1] | 16×16 MAC output |
| k, v, q vectors | INT8 signed | [-128, 127] | After requant |
| State S | INT24 signed | [-2^23, 2^23-1] | Persistent per head |
| α, β gates | INT8 unsigned | [0, 255] | After sigmoid/tanh approx |
| State output y | INT24 signed | [-2^23, 2^23-1] | q^T · S_new reduction |
| y for O projection | INT8 signed | [-128, 127] | After requant |
| O projection output | INT24 signed | [-2^23, 2^23-1] | Final accumulator |
| Norm output | INT8 signed | [-128, 127] | After RMSNorm |

### 2. INT24-to-INT8 Requantization

For K, V, Q projections and state output y:

```
// Fixed-point requant: shift + saturating clamp
function [7:0] requant_24_to_8(input signed [23:0] acc);
  reg signed [15:0] shifted;
  shifted = acc >>> 8;  // Arithmetic right shift by 8 bits
  if (shifted > 127) requant_24_to_8 = 127;
  else if (shifted < -128) requant_24_to_8 = -128;
  else requant_24_to_8 = shifted[7:0];
endfunction
```

Rationale: 16×16 MAC accumulates 256 products of INT4×INT8. Max product = 7×127 = 889. Max accumulator = 256×889 = 227,584 (fits in 18 bits). Shift by 8 brings to INT8 range with some headroom.

### 3. Physical SRAM Address Formula

Weight matrices are stored row-major, packed 64 INT4 elements per 256-bit word:

```
// Element (row, col) in matrix M at base address BASE
e = row * 128 + col           // Element index [0, 16383]
word = e / 64                 // Word index [0, 255]
bank = word % 6               // Bank [0, 5]
addr = BASE + word / 6        // Address within bank [0, 42] per matrix
lane = e % 64                 // 4-bit lane within word [0, 63]

// Matrix base addresses (each matrix uses 43 addresses per bank)
BASE_K = 0
BASE_V = 43
BASE_Q = 86
BASE_O = 129
BASE_CONV = 172  // Remaining 84 addresses for conv
```

### 4. Conv Storage Layout

α gate: 128 channels × 4 taps = 512 INT4 = 8 words  
β gate: 128 channels × 4 taps = 512 INT4 = 8 words  
History buffer: 128 channels × 3 taps = 384 INT8 = 12 words

```
// Conv addresses (starting at BASE_CONV = 172)
ALPHA_KERNEL = 172-173  // 8 words striped across 6 banks
BETA_KERNEL = 174-175   // 8 words striped
CONV_HISTORY = 176-183  // 12 words, holds last 3 timesteps
```

Conv schedule (10 cycles):
- Cycles 0-7: Process 16 channels/cycle (128 total)
- Cycles 8-9: PWL sigmoid/tanh pipeline drain

### 5. State SRAM Timing Contract

State bank layout: 128 rows × 3072 bits (128 elements × 24 bits)

Synchronous SRAM: read address cycle N → data available cycle N+1

644-cycle schedule with prefetch:
```
Phase       Cycles  Notes
K_PROJ      0-85    
V_PROJ      86-171  
Q_PROJ      172-257 
CONV        258-267 Prefetch state[0] during cycle 267
STATE_P1    268-395 Read row N, process row N-1 (pipelined)
STATE_D     396-397 Prefetch intermediate[0] during cycle 397
STATE_P2    398-525 Read row N, write row N-1, process row N-2
O_PROJ      526-611 y valid at cycle 526
NORM        612-635 
RESIDUAL    636-643 
```

### 6. MAC Scheduler

Both MAC arrays process same projection, different row ranges:
- MAC0: rows 0-63 (first half)
- MAC1: rows 64-127 (second half)

Weight fetch pattern (86 cycles per projection):
- 6 banks supply 6 words/cycle = 384 INT4 elements/cycle
- 2 MACs need 2×16×16 = 512 weights per compute cycle
- Prefetch 2 cycles ahead to sustain throughput

## Integration Checklist

- [ ] Requant units after K/V/Q MACs and after STATE_P2
- [ ] Physical address generators for weight striping
- [ ] Conv address generator with history update
- [ ] State prefetch timing (cross-phase)
- [ ] MAC row scheduler (0-63 vs 64-127)
- [ ] All blocks connected with correct precision

## Files to Copy from X8
- `rtl/fakeram45_128x256.v`
- `rtl/weight_sram_6bank.v`
- `rtl/state_sram_pingpong.v`
- `rtl/x8_controller.v`

## New Files for X9
- `rtl/requant_24_to_8.v` - Requantization unit
- `rtl/weight_addr_gen.v` - Striped address generator
- `rtl/conv_addr_gen.v` - Conv kernel/history address
- `rtl/mac_scheduler.v` - Row split scheduler
- `rtl/x9_datapath.v` - Full numerical datapath
- `rtl/x9_top.v` - Complete integration

## Target
- Full numerical integration (no shortcuts)
- All requant boundaries specified
- Yosys/ABC synthesis with timing estimate
- 500 MHz target (2.0 ns)
