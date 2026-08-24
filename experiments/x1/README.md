# X1: trials.jsonl Logging

## Heuristic System Version
Baseline with structured logging only. No lint rules, no regression tests, no failed directions memory.

## What's New
- Every design iteration logged to `trials.jsonl` with:
  - goal (what we're trying to achieve)
  - result (pass/fail, metrics)
  - timing (frequency achieved, slack)
  - drc (violations count)
  - area (mm²)
  - bugs_found (list)
  - learnings (what the iteration taught us)

## Y Iterations
- Y1: Fresh design from Kimi spec
- Y2-Y5: Learn from prior iterations, improve

## Target
Beat Kimi K3: 8721 tok/s @ 100 MHz, 4mm²
