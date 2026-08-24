# X6-Y1: Architecture Exploration

## Goal
Derive the optimal architecture configuration for a full KDA inference dataflow chip through quantitative analysis. **NO RTL in Y1.** This iteration outputs architecture decisions with full mathematical justification.

## Methodology: Show Your Math

Before any RTL exists, Y1 must answer these questions with explicit calculations:

### 1. Cycle Budget
- How many cycles per token?
- Break down by stage: K proj, V proj, Q proj, conv gates, state update, KDA query, O proj, norm, residual, writeback
- Pipeline depth and initiation interval

### 2. Bandwidth Math  
- Bytes read/written per stage
- Total memory traffic per token
- Required bus width to sustain target throughput
- SRAM bank count and arbitration strategy

### 3. Compute Utilization
- MAC ops per cycle vs theoretical peak
- Idle cycles due to memory stalls
- Bottleneck identification: compute-bound or memory-bound?

### 4. Area Budget
- Estimate mm² per block based on X1-X5 Nangate45 results:
  - 16×16 MAC array: ~0.17 mm² (from X4-Y5)
  - SRAM macro: ~0.5 mm² per 64KB (fakeram estimate)
  - Control FSM: ~0.01 mm²
  - Crossbar: ~0.02-0.05 mm² depending on ports
- Sum to verify <4mm² target

### 5. Pipeline Hazards
- Data dependencies between stages
- Where stalls occur
- How to avoid them (forwarding, buffering, reordering)

## Design Space Exploration

Evaluate these configurations:

| Config | MAC Arrays | SRAM Banks | Pipeline Depth | Notes |
|--------|------------|------------|----------------|-------|
| A      | 1          | 4          | 8              | Minimal, sequential |
| B      | 2          | 6          | 11             | Baseline from spec |
| C      | 2          | 8          | 11             | More memory parallelism |
| D      | 4          | 8          | 16             | Aggressive parallelism |

For each config, calculate:
- Cycles per token
- Throughput (tokens/sec at 500 MHz conservative, 750 MHz stretch)
- Total area estimate
- Memory bandwidth utilization

## Outputs

Y1 passes only if:
1. All calculations are internally consistent
2. Chosen config meets 10,000+ tok/s target
3. Chosen config fits in <4mm² area budget
4. Full math justification is documented

Files to produce:
- `architecture.json`: Chosen configuration with all parameters
- `architecture_rationale.md`: Full math derivation and justification
- `design_space_exploration.md`: Analysis of all evaluated configs

## Success Criteria

- [ ] Cycle budget calculated for each stage
- [ ] Bandwidth math shows feasibility
- [ ] Compute utilization >50% (not memory-starved)
- [ ] Area budget sums to <4mm²
- [ ] Pipeline hazards identified and addressed
- [ ] Best config chosen with justification
- [ ] All numbers internally consistent

## Non-Goals for Y1

- No RTL
- No testbenches  
- No synthesis/P&R
- No Verilog of any kind

Y2 will implement RTL for individual blocks based on Y1's architecture.
