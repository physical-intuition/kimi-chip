#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X4=$ROOT/experiments/x4
mkdir -p "$X4/build"
python3 "$X4/harness/lint_x4_y2.py" | tee "$X4/build/lint_y2.log"
iverilog -g2012 -s tb_x4_y2 -o "$X4/build/tb_x4_y2" "$X4/rtl/x4_y2_kimi.v" "$X4/tb/tb_x4_y2.v"
vvp "$X4/build/tb_x4_y2" | tee "$X4/build/functional_y2.log"
verilator --lint-only --timing -Wall --top-module x4_y2_kimi "$X4/rtl/x4_y2_kimi.v" >"$X4/build/verilator_y2.log" 2>&1
