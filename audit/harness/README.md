# Harness v2

Automated synthesis/P&R iteration harness for kimi-chip audit.

## Key improvements over X1-X7 harness

1. **Auto-parse critical path** - classifies as `sram_read | accumulator | mux | routing | etc`
2. **Memory bandwidth modeling** - estimates cycles/token and tokens/sec accounting for O(T) KV reads
3. **Plateau detection** - auto-bumps X version if 3+ Y iterations land within 5%
4. **Golden test** - verifies RTL matches nano-kpu reference (TODO: implement)
5. **Structured fix suggestions** - maps path types to concrete fixes

## Structure

```
harness/
├── config.py           # model config (nano-kpu), harness params
├── run_iteration.py    # main loop
├── scoring.py          # parse timing reports, classify paths
├── verify_golden.py    # compare RTL vs nano-kpu reference
├── trials.jsonl        # log of all X.Y runs
├── goals/              # goal text per iteration
│   └── x1_y1.txt
└── flow/               # OpenROAD configs
    ├── config.mk
    └── constraint.sdc
```

## Usage

```bash
# Run X1Y1 baseline (dry run first)
python run_iteration.py --x 1 --y 1 --dry-run

# Run X1Y1 for real
python run_iteration.py --x 1 --y 1

# Auto-increment from last trial
python run_iteration.py --auto

# Override goal
python run_iteration.py --x 1 --y 2 --goal "Try pipelining SRAM reads"
```

## Trial log format

Each line in `trials.jsonl`:
```json
{
  "x": 1,
  "y": 1,
  "goal": "...",
  "timestamp": "2026-09-10T14:45:00",
  "pass": false,
  "freq_mhz": 85.3,
  "target_freq_mhz": 100,
  "wns_ns": -1.47,
  "area_um2": 12345,
  "drc_count": 0,
  "critical_path_type": "sram_read",
  "suggestions": ["add read pipeline stage", "bank SRAM"],
  "bandwidth": {"est_tokens_per_sec": 1200, ...},
  "suggested_next_goal": "..."
}
```

## X version bumps

X bumps when:
- 3+ Y iterations plateau within 5% frequency
- Max Y reached (default 10)

X bump means changing the harness approach itself, not just RTL tweaks:
- X1: baseline RTL, measure
- X2: pipelined SRAM reads
- X3: banked SRAM
- X4: hierarchical accumulation
- etc.
