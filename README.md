# Kimi K3 Accelerator

Reimplementation and exploration of the Kimi K3 chip architecture using open-source EDA tools.

**Blog post:** [luoluo.ai/blog/kimi-k3](https://www.luoluo.ai/blog/kimi-k3)

## Quick Start

```bash
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
cd OpenROAD-flow-scripts
git clone https://github.com/physical-intuition/kimi-chip
cd flow && make DESIGN_CONFIG=../kimi-chip/experiments/x5/flow/config_y4.mk gds
```

The full flow runs in ~45 minutes on a decent machine.

## Structure

```
kimi-chip/
├── rtl/              # Verilog source files
├── tb/               # Testbenches
├── flow/             # ORFS configs and constraints
├── scripts/          # Rendering, screenshots, synthesis scripts
│   └── synth/        # Yosys synthesis scripts
├── docs/             # Blog drafts, iteration notes
├── results/          # GDS files, layout images, netlists
├── experiments/      # X1-X9 meta-harness experiments
│   └── x5/           # Best MAC array design (1 GHz+)
└── archives/         # Archived experiment artifacts
```

## Key Results

- **X5-Y4**: 1029 MHz on Nangate45 (MAC array only)
- **X7-Y5**: 728 MHz on full KDA dataflow

## Caveats

This uses Nangate45, an academic PDK. These results are simulation-only and would not directly translate to silicon tapeout. See the blog post for details.

## License

MIT
