#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
X1="$ROOT/experiments/x1"
ORFS=${ORFS:-/home/kit/OpenROAD-flow-scripts}

mkdir -p "$X1/build"
iverilog -g2012 -Wall -o "$X1/build/tb_x1_y2" \
  "$X1/rtl/x1_y2_kimi.v" "$X1/tb/tb_x1_y2.v"
vvp "$X1/build/tb_x1_y2"

make -f "$ORFS/flow/Makefile" \
  DESIGN_CONFIG="$X1/flow/config_y2.mk"
