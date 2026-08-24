#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
blocks=(mac_array_16x16 state_update conv_unit norm_unit residual_unit weight_crossbar activation_crossbar)
mkdir -p artifacts/logs artifacts/netlists
for block in "${blocks[@]}"; do
  echo "Synthesizing ${block}"
  yosys -s "flow/synth_${block}.ys" 2>&1 | tee "artifacts/logs/synth_${block}.log"
done
