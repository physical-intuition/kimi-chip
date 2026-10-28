#!/usr/bin/env bash
# X4Y2/X4Y3 regressions on the X4Y4 RTL. tb_bounds is the X4Y4 rewrite for the
# functional MLA (same intent: no out-of-range query/cache access, valid-entry
# traversal, full-cache backpressure, restart); tb_banked_4608 covers the new
# 9-bank KV macro. kv_banked_2048x64.v stays for tb_banked and reference_top.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rtl=(dataflow_top.v kv_banked_4608x64.v kv_banked_2048x64.v tests/fakeram_model.v)
for name in protocol mac_reference mac_pipeline debug_latency weight_equivalence bounds; do
  extra=()
  if [[ "$name" == weight_equivalence ]]; then extra+=(tests/reference_top.v); fi
  iverilog -g2012 -s "tb_$name" -o "$tmp/$name" "${rtl[@]}" "tests/tb_$name.v" ${extra[@]+"${extra[@]}"}
  vvp -n "$tmp/$name"
done
iverilog -g2012 -s tb -o "$tmp/bank" kv_banked_2048x64.v tests/fakeram_model.v tests/tb_banked.v
vvp -n "$tmp/bank"
iverilog -g2012 -s tb_banked_4608 -o "$tmp/bank9" kv_banked_4608x64.v tests/fakeram_model.v tests/tb_banked_4608.v
vvp -n "$tmp/bank9"
