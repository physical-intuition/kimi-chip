#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X4=$ROOT/experiments/x4
mkdir -p "$X4/build"
python3 "$X4/harness/lint_x4_y5.py" | tee "$X4/build/lint_y5.log"
iverilog -g2012 -s tb_x4_y5 -o "$X4/build/tb_x4_y5" "$X4/rtl/x4_y5_kimi.v" "$X4/tb/tb_x4_y5.v"
vvp "$X4/build/tb_x4_y5" | tee "$X4/build/functional_y5.log"
verilator --lint-only --timing -Wall -Wno-fatal --top-module x4_y5_kimi "$X4/rtl/x4_y5_kimi.v" >"$X4/build/verilator_y5.log" 2>&1
yosys -q -p "read_verilog -sv $X4/rtl/x4_y5_kimi.v; hierarchy -check -top x4_y5_kimi; proc; check" >"$X4/build/yosys_check_y5.log" 2>&1
echo LOCAL_Y5_PASS
