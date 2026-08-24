#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X4=$ROOT/experiments/x4
mkdir -p "$X4/build"
python3 "$X4/harness/lint_x4_y4.py" | tee "$X4/build/lint_y4.log"
iverilog -g2012 -s tb_x4_y4 -o "$X4/build/tb_x4_y4" "$X4/rtl/x4_y4_kimi.v" "$X4/tb/tb_x4_y4.v"
vvp "$X4/build/tb_x4_y4" | tee "$X4/build/functional_y4.log"
verilator --lint-only --timing -Wall -Wno-fatal --top-module x4_y4_kimi "$X4/rtl/x4_y4_kimi.v" >"$X4/build/verilator_y4.log" 2>&1
yosys -q -p "read_verilog -sv $X4/rtl/x4_y4_kimi.v; hierarchy -check -top x4_y4_kimi; proc; check" >"$X4/build/yosys_check_y4.log" 2>&1
echo LOCAL_Y4_PASS
