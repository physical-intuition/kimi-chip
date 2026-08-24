#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/kit/kimi-chip
X3=$ROOT/experiments/x3
mkdir -p "$X3/build"
python3 "$X3/regression/run_locked.py" | tee "$X3/build/functional_y1.log"
python3 "$ROOT/experiments/x2/lint/lint_rtl.py" --policy "$X3/lint/policy_y1.json" --report "$X3/build/lint_y1.json"
verilator --lint-only --timing -Wall --top-module x3_y1_kimi "$ROOT/experiments/x1/rtl/x1_y5_kimi.v" "$X3/rtl/x3_y1_kimi.v" >"$X3/build/verilator_y1.log" 2>&1 || true
make -C /home/kit/OpenROAD-flow-scripts/flow DESIGN_CONFIG="$X3/flow/config_y1.mk"
