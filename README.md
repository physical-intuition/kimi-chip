# Kimi K3 Accelerator

Reimplementing and pushing the limits of Kimi K3's inference chip using an LLM-powered meta-harness and open-source EDA tools.

**Blog post:** [luoluo.ai/blog/kimi-k3](https://www.luoluo.ai/blog/kimi-k3)

## Why ASICs?

GPUs launch a kernel per operation, each one round-tripping through off-chip HBM. An ASIC wires computation directly into silicon: no kernels, fixed pipeline, weights in on-chip SRAM. For nano models like K3 with fixed 128×128 state per head (no growing KV cache), everything fits on-chip.

## Results

| Phase | Design | Best Passing | vs K3's 100 MHz |
|-------|--------|--------------|-----------------|
| Phase 1 | 16×16 MAC array | **1047 MHz** (X5-Y5) | 10.5× |
| Phase 2 | Full KDA dataflow | **900 MHz** (X7-Y4) | 9× |

Both on Nangate45 (academic 45nm PDK), open-source flow (Yosys + OpenROAD).

## The Meta-Harness

This project uses an LLM agent that rewrites its own reasoning loop:

- **X versions**: harness generations (how the agent diagnoses problems)
- **Y iterations**: RTL attempts within one harness

When Y plateaus, the harness is wrong, not the design. X4's breakthrough (12→24-bit hierarchical fold) jumped from 468 MHz to 719 MHz. X5 crossed 1 GHz.

## Quick Start

```bash
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
cd OpenROAD-flow-scripts
git clone https://github.com/physical-intuition/kimi-chip
cd flow && make DESIGN_CONFIG=../kimi-chip/experiments/x5/flow/config_y4.mk gds
```

Takes ~45 minutes. Outputs GDS in `results/nangate45/kimi/base/`.

## Structure

```
kimi-chip/
├── rtl/              # Verilog source files
├── tb/               # Testbenches
├── flow/             # ORFS configs and constraints
├── scripts/          # Rendering, screenshots, synthesis
├── results/          # Layout images, netlists
└── experiments/      # X1-X7 meta-harness experiments
    ├── x5/           # Best MAC array (1047 MHz)
    └── x7/           # Full KDA dataflow (900 MHz)
```

## X/Y Iteration Matrix

```
        Y1      Y2      Y3      Y4      Y5
X1      fail    pass    463     451     455     baseline shift-drain
X2      469     467     468     470     468     banked accumulators  
X3      468     468     468     468     468     ceiling: 468 MHz
X4      719     783     837     900     909     12→24-bit hierarchical fold
X5      911     890     988     1029    1047    MAC pipeline + registered
X6      fail    fail    fail    fail    fail    RTL complete, ABC blocked
X7      fail    122     500     900     728     SRAM streaming, conv path
```

## Caveats

Nangate45 is an academic PDK with no real fab target. Real tapeout requires commercial PDKs (TSMC/Samsung/Intel), signoff tools (PrimeTime, Calibre), and many more checks. These frequency numbers won't directly translate to silicon.

## License

MIT
