# X6: KDA Dataflow Chip - Meta Harness

## Goal
Build a complete KDA inference dataflow chip. Each Y iteration is a FULL chip design attempt.

## What "Full Design" Means
Every Y iteration must produce:
1. Complete RTL for entire chip (not blocks in isolation)
2. Full testbench proving end-to-end data flow
3. Synthesis with timing analysis
4. If timing fails, analyze critical path and derive improvements for Y+1

## Architecture Target
- KDA recurrence: S_t = (I - β_t k_t k_t^T) · diag(α_t) · S_{t-1} + β_t k_t v_t^T
- 128×128 state matrix per head
- Target: 500 MHz, <3 mm²

## Y Iteration Structure

### Y1: First Complete Attempt
1. Design full chip RTL with all blocks connected
2. Write testbench that feeds input activations, runs full KDA computation, checks output
3. Run synthesis
4. Analyze timing, identify critical path
5. Log results to trials.jsonl

### Y2+: Improve Based on Y-1 Analysis
1. Read Y-1 timing report and critical path
2. Design architectural fix (e.g., pipeline stage, different datapath)
3. Implement complete chip with fix
4. Test, synthesize, analyze
5. Log improvements

## Stop Conditions
- Timing closes at 500 MHz → SUCCESS
- 5 consecutive Y iterations with no improvement → STOP
- Fundamental blocker that requires X7 redesign → STOP with documented blocker

## Key Rules
- NO partial implementations
- NO blocks with tied-low enables
- NO shortcuts (real data must flow through all stages)
- Every Y must be a complete, testable chip

## Files
- RTL: `/home/kit/kimi-chip/experiments/x6/rtl/`
- Tests: `/home/kit/kimi-chip/experiments/x6/tb/`
- Synthesis: `/home/kit/kimi-chip/experiments/x6/flow/`
- Artifacts: `/home/kit/kimi-chip/experiments/x6/artifacts/y{N}/`
- Trials: `/home/kit/kimi-chip/experiments/x6/trials.jsonl`
