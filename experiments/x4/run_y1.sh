#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X4=$ROOT/experiments/x4
mkdir -p "$X4/build"
python3 "$X4/harness/lint_x4_y1.py" | tee "$X4/build/lint_y1.log"
iverilog -g2012 -s tb_x4_y1 -o "$X4/build/tb_x4_y1" "$X4/rtl/x4_y1_kimi.v" "$X4/tb/tb_x4_y1.v"
vvp "$X4/build/tb_x4_y1" | tee "$X4/build/functional_y1.log"
verilator --lint-only --timing -Wall --top-module x4_y1_kimi "$X4/rtl/x4_y1_kimi.v" >"$X4/build/verilator_y1.log" 2>&1 || true
make -C /home/kit/OpenROAD-flow-scripts/flow DESIGN_CONFIG="$X4/flow/config_y1.mk"
