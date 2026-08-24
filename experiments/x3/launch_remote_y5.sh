#!/usr/bin/env bash
set -u
ROOT=/home/kit/kimi-chip
LOG="$ROOT/experiments/x3/build/orfs_y5.log"
MARKER="$ROOT/experiments/x3/.y5_flow_rc"
rm -f "$MARKER"
docker rm -f x3_y5_orfs >/dev/null 2>&1 || true
docker run --rm --name x3_y5_orfs \
  -v /home/kit/OpenROAD-flow-scripts/flow:/OpenROAD-flow-scripts/flow \
  -v /home/kit/kimi-chip:/home/kit/kimi-chip \
  -w /OpenROAD-flow-scripts/flow \
  openroad/orfs:latest \
  make DESIGN_CONFIG=/home/kit/kimi-chip/experiments/x3/flow/config_y5.mk \
  2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
printf 'FLOW_RC=%s\n' "$rc" | tee "$MARKER"
sleep 86400
