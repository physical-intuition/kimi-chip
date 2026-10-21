#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rtl="${RTL_DIR:-../x3y5_timing}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
iverilog -g2012 -s tb_golden -o "$tmp/sim" "$rtl/dataflow_top.v" "$rtl/kv_banked_2048x64.v" "$rtl/tests/fakeram_model.v" tb_golden.v
trace="${TRACE_PATH:-$tmp/trace}"
vvp "$tmp/sim" +TRACE="$trace"
python3 golden.py "$trace" "$@"
