# X8: KDA Dataflow Chip - Corrected Architecture

## Learnings from X7

X7 caught fundamental spec-level errors:

1. **O projection dependency**: O needs y = q^T · S_new, but was scheduled before STATE_P2
2. **Bank bandwidth math**: Single 256-bit bank delivers 22K bits in 86 cycles, but each projection needs 65K bits
3. **Weight capacity**: 6 fakeram45_128x256 = 24KB, but K/V/Q/O alone need 32KB
4. **State capacity**: 128×128 INT24 = 48KB, not 128KB

## X8 Corrected Architecture

### Weight SRAM (48 KiB total)
- 6 logical banks, each 256 words × 256 bits
- Each logical bank = 2 × fakeram45_128x256 macros (12 macros total)
- K/V/Q/O matrices striped across all 6 banks
- Address mapping: matrix[row][col] → bank[(row*128+col) % 6], addr[(row*128+col) / 6]

### State SRAM (96 KiB total for ping-pong)
- 128 rows × 128 cols × 24 bits = 48 KiB per state matrix
- 3072-bit wide interface (one full row)
- Implementation: 12 × fakeram45_128x256 slices per state bank
- Ping-pong: 24 macros total

### Corrected Pipeline Schedule (644 cycles)
```
Phase       Cycles  Description
K_PROJ      86      Both MACs: K = W_k × x (striped across 6 banks)
V_PROJ      86      Both MACs: V = W_v × x
Q_PROJ      86      Both MACs: Q = W_q × x
CONV        10      α, β gates (parallel)
STATE_P1    128     A = diag(α)·S, u = k^T·A
STATE_D     2       d = β(v - u)
STATE_P2    128     S_new = A + k·d^T, y = q^T·S_new
O_PROJ      86      Both MACs: O = W_o × y  ← AFTER state produces y
NORM        24      RMSNorm(output)
RESIDUAL    8       y = y + skip
TOTAL       644     cycles per token → 776K tok/s at 500 MHz
```

### Bandwidth Math (corrected)
- 6 banks × 256 bits/cycle = 1536 bits/cycle aggregate
- One 128×128 INT4 matrix = 65,536 bits = 256 words @ 256 bits
- 256 words ÷ 86 cycles = 2.98 words/cycle needed
- 6 banks supply 6 words/cycle → sufficient for 2 MACs reading different matrix regions
- Stripe pattern ensures no bank conflicts

### MAC Array Operation
- 2 × 16×16 arrays = 512 MACs
- During projection: both arrays work on same matrix, different rows
- Each array needs 128 words (32K bits) over 86 cycles
- 3 banks per array = 768 bits/cycle = 66K bits over 86 cycles ✓

## Integration Checklist
- [ ] Weight SRAM: 12 fakeram45_128x256 → 6 logical 256×256 banks
- [ ] State SRAM: 24 fakeram45_128x256 → 2 ping-pong 48KB banks
- [ ] Address striping logic for weight matrix access
- [ ] Bank arbiter for 6-bank aggregate reads
- [ ] K/V/Q projections before state update
- [ ] O projection AFTER STATE_P2 (depends on y output)
- [ ] Conv unit for α/β gates
- [ ] State update with real 2-pass operation
- [ ] Norm + residual
- [ ] Controller FSM with correct schedule

## Verification Requirements
Before synthesis:
- [ ] All 6 weight banks accessed during projections
- [ ] Both state banks used (ping-pong)
- [ ] O projection reads from state_p2 output, not shortcut
- [ ] Cycle count matches 644-cycle budget
- [ ] No tied-low MAC signals
- [ ] No constant/shortcut data paths

## Synthesis Setup
- Logic: `/home/kit/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib`
- SRAM: fakeram45_128x256 macros
- Target: 2.0 ns (500 MHz)

## Target Metrics
- 500 MHz timing closure (synthesis estimate)
- Area: ~0.7 mm² logic + ~2.5 mm² SRAM (36 macros)
- 776K tok/s throughput

## Success Criteria
- Complete integration with no shortcuts
- All verification checks pass
- Yosys/ABC synthesis completes with timing estimate
- Critical path identified for potential optimization
