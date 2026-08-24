# X1-Y1: First Design Iteration

## Goal
Design Kimi chip from spec using nangate45, no prior knowledge

## Starting Point
- Clean Kimi spec (KIMI_SPEC.md)
- nangate45 PDK
- OpenROAD flow

## Steps
1. Design RTL for 16x16 INT4 MAC array
2. Add SRAM interfaces (weights, activations, output)
3. Add simple controller
4. Synthesize with Yosys
5. Place & route with OpenROAD
6. Evaluate: frequency, area, DRC, timing

## Log to trials.jsonl
```json
{
  "x": 1,
  "y": 1,
  "timestamp": "...",
  "goal": "initial design from spec",
  "design": "x1_y1",
  "result": "pass/fail",
  "metrics": {
    "frequency_mhz": ...,
    "area_mm2": ...,
    "drc_violations": ...,
    "slack_ns": ...,
    "cell_count": ...
  },
  "bugs_found": [],
  "learnings": "..."
}
```
