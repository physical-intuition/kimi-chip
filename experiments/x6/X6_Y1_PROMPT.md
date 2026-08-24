# X6-Y1 Agent Prompt

You are designing the architecture for a full KDA (Kimi Delta Attention) inference dataflow chip.

## Your Task

Derive the optimal architecture configuration through quantitative analysis. **You must NOT write any RTL.** Your job is pure architecture exploration with explicit math.

## Target Specs

- Architecture: KDA with 128×128 state matrix per head
- Precision: INT4 weights, INT8 activations, INT24 accumulators  
- Throughput: 10,000+ tokens/sec
- Area: <4mm² on Nangate45
- Frequency: 500 MHz (conservative) to 750 MHz (stretch)

## Reference Architecture

See `X6_SPEC.md` for the baseline architecture with ASCII diagrams showing:
- Weight SRAM (6 banks) → Weight Crossbar → 2× MAC arrays + Conv Unit
- Activation Crossbar → KDA State Updater + Norm + Residual
- State SRAM (128KB) → Output Interface
- 11-stage pipeline, 12-state control FSM

## What You Must Calculate

### 1. Cycle Budget (per token)
Break down cycles for each operation:
- K projection: 128×128 INT4×INT8 GEMV on 16×16 MAC = ? cycles
- V projection: same as K
- Q projection: same as K  
- α gate: 1D conv with kernel 4 on 128 elements = ? cycles
- β gate: same as α
- State update: (I - βkk^T)·diag(α)·S + βkv^T for 128×128 matrix = ? cycles
- KDA query: q^T · S for 128×128 matrix = ? cycles
- O projection: same as K
- RMSNorm: 128 elements = ? cycles
- Residual add: 128 elements = ? cycles

Show your work. Example for K projection:
```
K projection: 128×128 matrix × 128 vector = 128 output elements
Each output = 128 INT4×INT8 MACs = 128 ops
16×16 MAC array = 256 MACs/cycle
Ops needed: 128×128 = 16,384
Cycles: 16,384 / 256 = 64 cycles
```

### 2. Bandwidth Requirements

For each stage, calculate bytes read/written:
```
K weights: 128×128×0.5 bytes (INT4) = 8KB read
K output: 128×1 byte (INT8) = 128B write
...
```

Sum total per token. Calculate required bus width:
```
Total: X KB per token
At 10K tok/s: X × 10K = Y MB/s
At 500 MHz with Z-bit bus: Z/8 × 500M = W MB/s
Utilization: Y / W = ?%
```

### 3. Area Budget

Use X1-X5 results as reference:
- 16×16 MAC array: 0.17 mm² (X4-Y5 at 909 MHz)
- fakeram45_512x64: ~0.1 mm² per macro
- Control logic: ~0.01 mm² per 1000 gates

Estimate area for:
- MAC arrays (×N)
- Weight SRAM (6 banks × size)
- State SRAM (KDA state + activation buffers)
- Crossbars
- Conv unit
- KDA state updater  
- Norm unit
- Control FSM

Sum must be <4mm².

### 4. Pipeline Schedule

Draw a cycle-by-cycle schedule showing what each unit does:
```
Cycle | MAC0 | MAC1 | Conv | KDA | Norm | Out
------+------+------+------+-----+------+----
  0   | K[0] |      |      |     |      |
  1   | K[1] |      |      |     |      |
...
```

Identify:
- Pipeline depth
- Initiation interval (cycles between consecutive tokens)
- Any stalls or bubbles

### 5. Design Space Exploration

Evaluate at least 3 configurations:
- Conservative (1 MAC, sequential)
- Baseline (2 MACs, pipelined)
- Aggressive (4 MACs, parallel)

For each, calculate throughput and area. Choose the best.

## Outputs

Create these files in `/home/kit/kimi-chip/experiments/x6/`:

1. `architecture.json`:
```json
{
  "num_mac_arrays": 2,
  "mac_array_size": [16, 16],
  "weight_sram_banks": 6,
  "weight_sram_size_kb": 512,
  "state_sram_size_kb": 128,
  "bus_width_bits": 256,
  "pipeline_depth": 11,
  "initiation_interval": 2,
  "target_frequency_mhz": 500,
  "estimated_area_mm2": 3.2,
  "estimated_throughput_toks": 15000
}
```

2. `architecture_rationale.md`: Full derivation showing ALL calculations

3. `design_space_exploration.md`: Analysis of all configs evaluated

## Rules

- Show ALL math. No hand-waving.
- Every number must be derived from first principles or prior X1-X5 evidence.
- If you're unsure about a parameter, state your assumption explicitly.
- Internal consistency is mandatory: throughput calculation must match cycle budget.
- NO RTL. This is architecture exploration only.

## Success Criteria

- [ ] Cycle budget complete for all stages
- [ ] Bandwidth math proves memory is not the bottleneck
- [ ] Area sum <4mm² with breakdown
- [ ] Pipeline schedule drawn
- [ ] ≥3 configs evaluated
- [ ] Best config chosen with justification
- [ ] architecture.json created
- [ ] architecture_rationale.md created
- [ ] All numbers internally consistent
