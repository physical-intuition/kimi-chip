#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X2=$ROOT/experiments/x2
mkdir -p "$X2/build"
python3 "$X2/lint/lint_rtl.py" --policy "$X2/lint/policy_y1.json" --report "$X2/build/lint_y1.json"
iverilog -g2012 -Wall -s tb_x2_y1 -o "$X2/build/tb_x2_y1" "$ROOT/experiments/x1/rtl/x1_y5_kimi.v" "$X2/rtl/x2_y1_kimi.v" "$X2/tb/tb_x2_y1.v"
vvp "$X2/build/tb_x2_y1"
verilator --lint-only --timing -Wall --top-module x2_y1_kimi "$ROOT/experiments/x1/rtl/x1_y5_kimi.v" "$X2/rtl/x2_y1_kimi.v" || true
make -C /home/kit/OpenROAD-flow-scripts/flow DESIGN_CONFIG="$X2/flow/config_y1.mk"
