# X6: Full KDA Inference Dataflow Chip

## Goal
Design a complete dataflow ASIC for Kimi K3-style KDA (Kimi Delta Attention) inference.
Not just the MAC array - the entire pipeline from weight fetch to output writeback.

## Target Specs
- Architecture: KDA with 128×128 state matrix per head
- Precision: INT4 weights, INT8 activations, INT24 accumulators
- Throughput: 10,000+ tokens/sec
- Area: <4mm² on Nangate45
- Power: <500mW (estimate)

---

## Chip Layout (Top-Level)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WEIGHT SRAM (512KB)                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │ Bank 0  │ │ Bank 1  │ │ Bank 2  │ │ Bank 3  │ │ Bank 4  │ │ Bank 5  │   │
│  │  K wts  │ │  V wts  │ │  Q wts  │ │  O wts  │ │ conv α  │ │ conv β  │   │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘   │
└───────┼──────────┼──────────┼──────────┼──────────┼──────────┼─────────────┘
        │          │          │          │          │          │
        ▼          ▼          ▼          ▼          ▼          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WEIGHT CROSSBAR (6→2)                             │
│                    routes weights to MAC arrays on demand                   │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│   MAC ARRAY   │       │   MAC ARRAY   │       │   CONV UNIT   │
│    16×16      │       │    16×16      │       │   (α, β gates)│
│   (GEMV 0)    │       │   (GEMV 1)    │       │               │
│               │       │               │       │  1D conv +    │
│  K/V proj     │       │  Q/O proj     │       │  sigmoid/tanh │
└───────┬───────┘       └───────┬───────┘       └───────┬───────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ACTIVATION CROSSBAR (3→4)                            │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│  KDA STATE    │       │    NORM       │       │   RESIDUAL    │
│   UPDATER     │       │   (RMSNorm)   │       │     ADD       │
│               │       │               │       │               │
│ S = (I-βkk^T) │       │  x/√(Σx²/d)   │       │   x + skip    │
│  ·diag(α)·S   │       │               │       │               │
│  + βkv^T      │       │               │       │               │
└───────┬───────┘       └───────┬───────┘       └───────┬───────┘
        │                       │                       │
        └───────────────────────┼───────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         STATE SRAM (128KB)                                  │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────┐  │
│  │   KDA State Matrix   │  │   Activation Buffer  │  │   Skip Buffer    │  │
│  │   128×128 per head   │  │   (ping-pong)        │  │   (residual)     │  │
│  └──────────────────────┘  └──────────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         OUTPUT INTERFACE                                    │
│                    (next token logits / embeddings)                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Pipeline Stages (Per Token)

```
Time →
     ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
     │ T0 │ T1 │ T2 │ T3 │ T4 │ T5 │ T6 │ T7 │ T8 │ T9 │T10 │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
MAC0 │ K  │ K  │ V  │ V  │    │    │    │    │    │    │    │
     │proj│proj│proj│proj│    │    │    │    │    │    │    │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
MAC1 │    │    │ Q  │ Q  │ O  │ O  │    │    │    │    │    │
     │    │    │proj│proj│proj│proj│    │    │    │    │    │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
CONV │    │ α  │ α  │ β  │ β  │    │    │    │    │    │    │
     │    │gate│gate│gate│gate│    │    │    │    │    │    │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
KDA  │    │    │    │    │updt│updt│qry │qry │    │    │    │
     │    │    │    │    │ S  │ S  │ Sq │ Sq │    │    │    │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
NORM │    │    │    │    │    │    │    │norm│norm│    │    │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
RES  │    │    │    │    │    │    │    │    │add │add │    │
─────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
OUT  │    │    │    │    │    │    │    │    │    │wr  │wr  │
─────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘

Pipeline depth: 11 cycles
Throughput: 1 token every 2 cycles (after pipeline fills)
At 500 MHz: 250M tokens/sec theoretical, ~50K tokens/sec practical with memory
```

---

## Memory Bandwidth Requirements

```
Per token:
  K proj: 128×128 INT4 weights = 8KB read
  V proj: 128×128 INT4 weights = 8KB read  
  Q proj: 128×128 INT4 weights = 8KB read
  O proj: 128×128 INT4 weights = 8KB read
  Conv:   2×128 INT4 weights   = 128B read
  State:  128×128 INT8 matrix  = 16KB read + 16KB write
  
  Total per token: ~64KB memory traffic
  
  At 10K tok/s: 640 MB/s sustained bandwidth
  At 500 MHz with 256-bit bus: 16 GB/s available
  
  Headroom: 25× → can batch or run multiple heads
```

---

## Detailed Block Specs

### MAC Array (×2)
- Size: 16×16 = 256 MACs
- Precision: INT4 × INT8 → INT24 accumulator
- Architecture: weight-stationary systolic
- Frequency target: 750+ MHz (proven in X4/X5)
- Features:
  - Banked accumulators (16 banks × 16 accumulators)
  - Hierarchical fold (12-bit → 24-bit every 16 products)
  - Double-buffered weight loading

### Conv Unit
- 1D convolution for α, β gate computation
- Kernel size: 4 (typical for KDA)
- Activation: sigmoid for α, tanh for β
- LUT-based or piecewise-linear approximation

### KDA State Updater
- Core recurrence: S_t = (I - β_t k_t k_t^T) · diag(α_t) · S_{t-1} + β_t k_t v_t^T
- 128×128 matrix operations
- Optimizations:
  - Rank-1 update structure (β_t k_t k_t^T and β_t k_t v_t^T)
  - Diagonal scaling (diag(α_t)) is element-wise
  - Can reuse MAC arrays for matrix-vector products

### Norm Unit
- RMSNorm: x / √(mean(x²) + ε)
- Pipelined: accumulate squares → divide → multiply
- Fixed-point with scaling

### Residual Add
- Simple addition with saturation
- Skip connection buffer

---

## Control FSM States

```
┌─────────────┐
│    IDLE     │◄─────────────────────────────────────┐
└──────┬──────┘                                      │
       │ token_valid                                 │
       ▼                                             │
┌─────────────┐                                      │
│  FETCH_K    │ load K weights, start K projection   │
└──────┬──────┘                                      │
       │ k_done                                      │
       ▼                                             │
┌─────────────┐                                      │
│  FETCH_V    │ load V weights, start V projection   │
└──────┬──────┘                                      │
       │ v_done                                      │
       ▼                                             │
┌─────────────┐                                      │
│  FETCH_Q    │ load Q weights, start Q projection   │
└──────┬──────┘                                      │
       │ q_done                                      │
       ▼                                             │
┌─────────────┐                                      │
│  CONV_GATE  │ compute α, β gates                   │
└──────┬──────┘                                      │
       │ gates_done                                  │
       ▼                                             │
┌─────────────┐                                      │
│ STATE_UPDATE│ update KDA state matrix              │
└──────┬──────┘                                      │
       │ state_done                                  │
       ▼                                             │
┌─────────────┐                                      │
│  KDA_QUERY  │ query: output = q^T · S              │
└──────┬──────┘                                      │
       │ query_done                                  │
       ▼                                             │
┌─────────────┐                                      │
│  FETCH_O    │ load O weights, output projection    │
└──────┬──────┘                                      │
       │ o_done                                      │
       ▼                                             │
┌─────────────┐                                      │
│    NORM     │ RMSNorm                              │
└──────┬──────┘                                      │
       │ norm_done                                   │
       ▼                                             │
┌─────────────┐                                      │
│  RESIDUAL   │ add skip connection                  │
└──────┬──────┘                                      │
       │ res_done                                    │
       ▼                                             │
┌─────────────┐                                      │
│  WRITEBACK  │ output to next layer / external      │
└──────┬──────┘                                      │
       │ wb_done                                     │
       └─────────────────────────────────────────────┘
```

---

## Verification Strategy

### Level 1: Block-Level
- Each block (MAC, Conv, KDA, Norm, Residual) tested independently
- Golden model: Python/NumPy reference
- Test vectors: random + corner cases

### Level 2: Pipeline Integration
- Full pipeline with dummy memory
- Check data flow between stages
- Verify no pipeline stalls/bubbles

### Level 3: Memory Integration  
- Real SRAM models (fakeram45_*)
- Bandwidth stress tests
- Memory arbitration correctness

### Level 4: End-to-End
- Single token inference
- Compare against PyTorch KDA layer
- Bit-exact or within tolerance

---

## Tools Required

### Have (from X1-X5)
- [x] LLM RTL generation (SystemVerilog)
- [x] Verilator lint
- [x] Icarus Verilog simulation
- [x] Yosys synthesis
- [x] OpenROAD place & route
- [x] KLayout GDS export
- [x] trials.jsonl + heuristic learning
- [x] Testbench generation

### Need to Add
- [ ] **SRAM compiler** - OpenRAM or fakeram for memory macros
- [ ] **NoC generator** - for crossbar/interconnect (or hand-write simple crossbar)
- [ ] **System testbench** - end-to-end inference validation
- [ ] **Power estimator** - OpenROAD power analysis or Joules
- [ ] **Hierarchical P&R** - may need to P&R blocks separately then integrate

---

## Success Criteria

1. **Functional**: Single-token inference matches PyTorch KDA layer (within INT tolerance)
2. **Timing**: All blocks meet 500 MHz (conservative) or 750 MHz (stretch)
3. **Area**: Total chip <4mm² on Nangate45
4. **DRC/LVS**: Clean GDS with no violations
5. **Power**: <500mW estimated (stretch: <300mW)

---

## Iteration Plan

### X6-Y1: Architecture Exploration (no RTL, show your math)
- NO RTL in Y1. Pure architecture reasoning with quantitative analysis.
- Required calculations before any RTL:
  1. **Cycle budget**: How many cycles per token? Break down by stage.
  2. **Bandwidth math**: Bytes read/written per stage, total per token, required bus width.
  3. **Compute utilization**: MAC ops per cycle vs theoretical peak, identify bottlenecks.
  4. **Area budget**: Estimate mm² per block based on X1-X5 results, sum to check <4mm².
  5. **Pipeline hazards**: Data dependencies, where stalls occur, how to avoid them.
- Explore: 1 vs 2 MAC arrays, memory banking (4/6/8 banks), pipeline depth (8/11/16 stages)
- Output: `architecture.json` with chosen config + full math justification in `architecture_rationale.md`
- Y1 passes only if all calculations are internally consistent and meet target specs

### X6-Y2: Block RTL Generation
- Generate RTL for each block independently
- Reuse MAC array from X4/X5 (proven 909 MHz)
- New blocks: Conv, KDA State, Norm, Residual, Control FSM

### X6-Y3: Integration
- Wire blocks together
- Add crossbars/interconnect
- Integrate SRAM macros

### X6-Y4: Pipeline Verification
- End-to-end simulation
- Fix timing/stalls
- Verify data integrity

### X6-Y5: Physical Implementation
- Full-chip OpenROAD
- Timing closure at system level
- Area/power analysis

### X6-Y6+: Optimization
- Iterate on bottlenecks
- Push frequency
- Reduce area/power
