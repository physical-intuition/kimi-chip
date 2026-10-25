#!/usr/bin/env bash
# X4Y4: MLA operator RTL vs the bit-exact model (exact, every tensor and the
# KV-cache SRAM image) and vs the normative reference model.py (cosine), KDA
# exactness in the same runs, full-cache backpressure, group-64 weights, and
# mutation self-checks. Needs iverilog and a python3 with numpy (PYTHON=...).
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-python3}"
"$PY" -c "import numpy" 2>/dev/null || { echo "FAIL numpy required for reference/model.py (set PYTHON=...)"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Generated artifacts must be reproducible from their disclosed generators.
"$PY" mla_model.py luts "$tmp/mla_luts.vh"; cmp "$tmp/mla_luts.vh" mla_luts.vh
python3 test_mla.py
"$PY" test_reference.py
rtl=(dataflow_top.v kv_banked_4608x64.v tests/fakeram_model.v tb_mla.v)
iverilog -g2012 -s tb_mla -o "$tmp/sim128" "${rtl[@]}"
iverilog -g2012 -s tb_mla -Ptb_mla.GROUP_SIZE=64 -o "$tmp/sim64" "${rtl[@]}"
"$PY" mla_model.py hex "$tmp/w64" 64
noxz() { if awk '{for(i=2;i<=NF;i++) if($i ~ /[xzXZ]/) bad=1} END{exit !bad}' "$1"; then echo "FAIL unknown values in $1"; exit 1; fi; }

# A: 6 tokens, 2 sequences (restart mid-run) -- the X4Y3 KDA sequence
printf '0 1\n1 0\n511 0\n7 0\n42 1\n3 0\n' > "$tmp/seqA"
vvp -n "$tmp/sim128" +TRACE="$tmp/A" +SEQ="$tmp/seqA" > /dev/null
noxz "$tmp/A"
"$PY" golden_mla.py "$tmp/A" > "$tmp/A.json"
python3 golden_kda.py "$tmp/A" > /dev/null
echo "PASS A: 6 tokens / 2 sequences, MLA + KDA exact, reference min out cos $("$PY" -c "import json;print(round(json.load(open('$tmp/A.json'))['ref_min_cos'],6))")"

# B: public prompts 0+1 as one 64-token sequence (cache full), refused token, restart
"$PY" -c "
import nano_ref
a, b = nano_ref.public_tokens(); s = a + b
lines = [f'{t} {int(i == 0)}' for i, t in enumerate(s)] + [f'PROBE {b[2]}', f'{b[0]} 1', f'{b[1]} 0']
open('$tmp/seqB', 'w').write('\n'.join(lines) + '\n')"
vvp -n "$tmp/sim128" +TRACE="$tmp/B" +SEQ="$tmp/seqB" > /dev/null
noxz "$tmp/B"
"$PY" golden_mla.py "$tmp/B" > "${MLA_REPORT:-$tmp/B.json}"
python3 golden_kda.py "$tmp/B" > /dev/null
echo "PASS B: 64-entry cache + refused token + restart (66 tokens), MLA + KDA exact, reference min out cos $("$PY" -c "import json;print(round(json.load(open('${MLA_REPORT:-$tmp/B.json}'))['ref_min_cos'],6))")"

# C: group_size 64 weights (two groups on wk_c / wv)
printf '5 1\n300 0\n17 0\n511 1\n2 0\n' > "$tmp/seqC"
vvp -n "$tmp/sim64" +TRACE="$tmp/C" +SEQ="$tmp/seqC" +MLA_WDIR="$tmp/w64" > /dev/null
noxz "$tmp/C"
"$PY" golden_mla.py "$tmp/C" --group 64 --wdir "$tmp/w64" > /dev/null
echo "PASS C: group_size 64, 5 tokens / 2 sequences, MLA exact"

# Mutations: the comparison must reject one corrupted value of each kind.
mut() {  # $1 key, $2 field index (1-based after key), $3 trace, $4 label
  awk -v k="$1" -v f="$2" '$1==k && !done {$(f+1)=$(f+1) "1"; done=1} {print}' "$3" > "$tmp/bad"
  if "$PY" golden_mla.py "$tmp/bad" --no-ref > /dev/null 2>&1; then echo "FAIL mutation not detected: $4"; exit 1; fi
}
mut m_kv 50 "$tmp/A" "KV cache word"
mut m_p 2 "$tmp/A" "softmax probability"
mut m_lat 7 "$tmp/A" "latent norm"
mut m_out 13 "$tmp/A" "MLA output"
awk '$1=="PROBE" {$3=63} {print}' "$tmp/B" > "$tmp/bad"
if "$PY" golden_mla.py "$tmp/bad" --no-ref > /dev/null 2>&1; then echo "FAIL mutation not detected: probe count"; exit 1; fi
echo "PASS MLA RTL exactly matches mla_model.int_step (A, B, C); 5 mutations rejected"
