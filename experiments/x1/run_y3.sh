#!/usr/bin/env bash
set -euo pipefail

X1=/home/kit/kimi-chip/experiments/x1
mkdir -p "$X1/build"

iverilog -g2012 -Wall -o "$X1/build/tb_x1_y3" \
  "$X1/rtl/x1_y3_kimi.v" "$X1/tb/tb_x1_y3.v"
vvp "$X1/build/tb_x1_y3"

make -C /home/kit/OpenROAD-flow-scripts/flow \
  DESIGN_CONFIG="$X1/flow/config_y3.mk"
