#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X5=$ROOT/experiments/x5
mkdir -p "$X5/build"
python3 "$X5/harness/lint_y2.py" | tee "$X5/build/lint_y2.log"
iverilog -g2012 -s tb_x5_y2 -o "$X5/build/tb_x5_y2" "$X5/rtl/x5_y2_kimi.v" "$X5/tb/tb_x5_y2.v"
vvp "$X5/build/tb_x5_y2" | tee "$X5/build/functional_y2.log"
verilator --lint-only --timing -Wall -Wno-fatal --top-module x5_y2_kimi "$X5/rtl/x5_y2_kimi.v" >"$X5/build/verilator_y2.log" 2>&1
yosys -q -p "read_verilog -sv $X5/rtl/x5_y2_kimi.v; hierarchy -check -top x5_y2_kimi; proc; check" >"$X5/build/yosys_check_y2.log" 2>&1
echo LOCAL_X5_Y2_PASS
