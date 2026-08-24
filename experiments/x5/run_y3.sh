#!/usr/bin/env bash
set -euo pipefail
X5=/home/kit/kimi-chip/experiments/x5
mkdir -p "$X5/build"
python3 "$X5/harness/derive_y3.py" | tee "$X5/harness/derive_y3.log"
python3 "$X5/harness/lint_y3.py" | tee "$X5/build/lint_y3.log"
iverilog -g2012 -s tb_x5_y3 -o "$X5/build/tb_x5_y3" "$X5/rtl/x5_y3_kimi.v" "$X5/tb/tb_x5_y3.v"
vvp "$X5/build/tb_x5_y3" | tee "$X5/build/functional_y3.log"
verilator --lint-only --timing -Wall -Wno-fatal --top-module x5_y3_kimi "$X5/rtl/x5_y3_kimi.v" >"$X5/build/verilator_y3.log" 2>&1
yosys -q -p "read_verilog -sv $X5/rtl/x5_y3_kimi.v; hierarchy -check -top x5_y3_kimi; proc; check" >"$X5/build/yosys_check_y3.log" 2>&1
echo LOCAL_X5_Y3_PASS
