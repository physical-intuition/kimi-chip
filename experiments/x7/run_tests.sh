#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 experiments/x7/tb/gen_vectors.py
mkdir -p experiments/x7/build experiments/x7/artifacts/y1
iverilog -g2012 -s tb_x7_units -o experiments/x7/build/tb_x7_units experiments/x7/rtl/*.v experiments/x7/tb/tb_x7_units.v
vvp experiments/x7/build/tb_x7_units | tee experiments/x7/artifacts/y1/unit_tests.log
iverilog -g2012 -s tb_x7_top -o experiments/x7/build/tb_x7_top experiments/x7/rtl/*.v experiments/x7/tb/tb_x7_top.v
vvp experiments/x7/build/tb_x7_top | tee experiments/x7/artifacts/y1/top_test.log
