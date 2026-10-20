#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for name in protocol mac_reference mac_pipeline debug_latency weight_equivalence; do
  extra=()
  if [[ "$name" == weight_equivalence ]]; then extra+=(tests/reference_top.v); fi
  iverilog -g2012 -s "tb_$name" -o "$tmp/$name" dataflow_top.v kv_banked_2048x64.v tests/fakeram_model.v "tests/tb_$name.v" "${extra[@]}"
  vvp "$tmp/$name"
done
iverilog -g2012 -s tb -o "$tmp/bank" kv_banked_2048x64.v tests/fakeram_model.v tests/tb_banked.v
vvp "$tmp/bank"
