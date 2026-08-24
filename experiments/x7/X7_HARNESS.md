# X7 Harness: Full Dataflow Chip Iterations

## Methodology
Each Y iteration is a COMPLETE chip design attempt:
1. Full RTL for entire chip
2. Full testbench proving end-to-end data flow
3. Yosys+ABC synthesis with timing analysis
4. If timing fails, analyze critical path and derive Y+1 fix

## Critical Architecture Decisions (MUST follow)

### SRAM Macros
- Use `fakeram45_512x64` explicitly - do NOT use `reg [N:0] mem [0:M]`
- Yosys `memory -nomap` keeps macros as blackboxes
- Instantiate macros directly, not inferred

### Iterative RMSNorm
- MUST be pipelined, NOT combinational
- Process 16 elements/cycle over 8 cycles for accumulation
- Newton-Raphson reciprocal sqrt in 6 cycles
- Total ~24 cycles, NOT 109K gates

### Serialized Datapath
- Single 16×16 MAC array
- Time-multiplex across projections
- Process 16 output lanes at a time

## Stop Conditions
- SUCCESS: Timing closes at 500 MHz (delay ≤ 2.0 ns)
- FAIL after 5 consecutive Y iterations with no timing improvement
- FUNDAMENTAL BLOCKER requiring X8 redesign

## Rules
- NO partial implementations
- NO tied-low enables
- NO shortcuts (output must depend on input through entire path)
- Every Y must be complete and testable
- Log EVERY iteration to trials.jsonl with real metrics
