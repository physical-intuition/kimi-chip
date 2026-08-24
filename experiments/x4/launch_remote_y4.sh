#!/usr/bin/env bash
set -u
ROOT=/home/kit/kimi-chip
X4="$ROOT/experiments/x4"
LOG="$X4/build/orfs_y4.log"
MARKER="$X4/.y4_flow_rc"
MIN_FREE_KB=$((10 * 1024 * 1024))
free_kb=$(df -Pk / | awk 'NR==2 {print $4}')
if [[ ! "$free_kb" =~ ^[0-9]+$ ]] || (( free_kb < MIN_FREE_KB )); then
  printf 'FLOW_RC=75\n' | tee "$MARKER"
  printf 'BLOCKER insufficient_disk free_kb=%s required_kb=%s\n' "$free_kb" "$MIN_FREE_KB" | tee "$LOG"
  exit 75
fi
rm -f "$MARKER"
mkdir -p "$X4/build"
docker rm -f x4_y4_orfs >/dev/null 2>&1 || true
docker run --rm --name x4_y4_orfs \
  -v /home/kit/OpenROAD-flow-scripts/flow:/OpenROAD-flow-scripts/flow \
  -v /home/kit/kimi-chip:/home/kit/kimi-chip \
  -w /OpenROAD-flow-scripts/flow \
  openroad/orfs:latest \
  bash -lc 'set +e
    make DESIGN_CONFIG=/home/kit/kimi-chip/experiments/x4/flow/config_y4.mk
    rc=$?
    src=/OpenROAD-flow-scripts/flow
    artifact=/home/kit/kimi-chip/experiments/x4/artifacts/y4
    tmp=/home/kit/kimi-chip/experiments/x4/artifacts/.y4.tmp.$$
    rm -rf "$tmp"
    mkdir -p "$tmp"/{logs,reports,results,objects}
    cp -a "$src/logs/nangate45/x4_y4_kimi/base/." "$tmp/logs/" 2>/dev/null || true
    cp -a "$src/reports/nangate45/x4_y4_kimi/base/." "$tmp/reports/" 2>/dev/null || true
    cp -a "$src/results/nangate45/x4_y4_kimi/base/." "$tmp/results/" 2>/dev/null || true
    cp -a "$src/objects/nangate45/x4_y4_kimi/base/." "$tmp/objects/" 2>/dev/null || true
    printf "FLOW_RC=%s\n" "$rc" > "$tmp/flow_rc"
    rm -rf "$artifact"
    mv "$tmp" "$artifact"
    exit "$rc"' \
  2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
printf 'FLOW_RC=%s\n' "$rc" | tee "$MARKER"
sleep 86400
