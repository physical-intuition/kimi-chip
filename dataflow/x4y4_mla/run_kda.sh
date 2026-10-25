#!/usr/bin/env bash
# X4Y3 regression on the X4Y4 RTL: KDA operator RTL vs bit-exact golden model, plus mutation self-check.
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 kda_model.py luts
python3 test_kda.py
iverilog -g2012 -s tb_kda -o "$tmp/sim" dataflow_top.v kv_banked_4608x64.v tests/fakeram_model.v tb_kda.v
vvp "$tmp/sim" +TRACE="$tmp/kda.trace"
if awk '{for(i=2;i<=NF;i++) if($i ~ /[xzXZ]/) bad=1} END{exit !bad}' "$tmp/kda.trace"; then echo "FAIL unknown values in KDA dump"; exit 1; fi
python3 golden_kda.py "$tmp/kda.trace" > "${KDA_REPORT:-$tmp/report.json}"
# The comparison must reject a single corrupted state word.
awk '$1=="S" && !done {$100=$100+1; done=1} {print}' "$tmp/kda.trace" > "$tmp/bad.trace"
if python3 golden_kda.py "$tmp/bad.trace" > /dev/null; then echo "FAIL mutation not detected"; exit 1; fi
echo "PASS KDA RTL exactly matches kda_model.int_step (6 tokens, 2 sequences); mutation rejected"
