#!/usr/bin/env bash
# X4Y6 regression: full decoder token -> embedding ROM -> L0 (KDA, res_mlp mix,
# norm2, MoE) -> L1 (res_attn mix, norm1, MLA, res_mlp mix, norm2, MoE) -> res_out
# mix -> final RMSNorm -> LM head (512 logits) -> argmax, RTL vs the bit-exact
# decoder_model.py (every tensor, all logits, the argmax port, KV-cache SRAM image).
# Exactness is the gate. The distance to reference/model.py RefModel.step (official
# embedding + X4Y3 KDA placeholders) is reported per row (logits cosine, bar 0.98),
# with MoE selection and argmax differences listed. Plus mutation self-checks.
# Needs iverilog and python3 with numpy (PYTHON=...). ~15 s of simulation per token.
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-python3}"
"$PY" -c "import numpy" 2>/dev/null || { echo "FAIL numpy required for reference/model.py (set PYTHON=...)"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rtl=(dataflow_top.v kv_banked_4608x64.v tests/fakeram_model.v tb_decoder.v)

# LUTs and ROM images must be reproducible from their generators.
"$PY" -c "import kda_model; print(kda_model.gen_luts_vh(), end='')" | cmp -s - kda_luts.vh || { echo "FAIL kda_luts.vh not reproducible"; exit 1; }
"$PY" mla_model.py luts "$tmp/mla_luts.vh"; cmp -s "$tmp/mla_luts.vh" mla_luts.vh || { echo "FAIL mla_luts.vh not reproducible"; exit 1; }
"$PY" decoder_model.py hex "$tmp/w128" 128
for f in moe_q moe_s moe_z small emb_q emb_s emb_z head_q head_s head_z mla/q mla/s mla/z mla/knorm; do
  cmp -s "$tmp/w128/$f.hex" "glue_weights/$f.hex" || { echo "FAIL glue_weights/$f.hex not reproducible"; exit 1; }
done
iverilog -g2012 -s tb_decoder -o "$tmp/sim128" "${rtl[@]}"
iverilog -g2012 -s tb_decoder -Ptb_decoder.GROUP_SIZE=64 -o "$tmp/sim64" "${rtl[@]}"
"$PY" decoder_model.py hex "$tmp/w64" 64
noxz() { if awk '{for(i=2;i<=NF;i++) if($i ~ /[xzXZ]/) bad=1} END{exit !bad}' "$1"; then echo "FAIL unknown values in $1"; exit 1; fi; }
run() { vvp -n "$1" +TRACE="$2" +SEQ="$3" +MLA_WDIR="$4/mla" +GLUE_WDIR="$4" > /dev/null; noxz "$2"; }
summ() { tail -1 "$1" | "$PY" -c 'import json,sys; d=json.loads(sys.stdin.read()); print("min cos", d["min_cos"], "mean logits cos", d["mean_cos_logits"], "rows<0.98", [(r["index"], r["cos_logits"]) for r in d["rows_below_bar"]], "argmax flips", [(f["index"], f["int_argmax"], f["ref_argmax"], f["ref_top2_gap"]) for f in d["argmax_flips"]], "top-k flips", [(f["index"], f["layer"], f["ref_key_gap"]) for f in d["topk_flips"]])'; }

# A: 6 tokens, 2 sequences
printf '0 1\n1 0\n511 0\n7 0\n42 1\n3 0\n' > "$tmp/seqA"
run "$tmp/sim128" "$tmp/A" "$tmp/seqA" glue_weights
"$PY" golden_decoder.py "$tmp/A" > "$tmp/A.json" || { cat "$tmp/A.json"; echo "FAIL A"; exit 1; }
echo "PASS A: 6 tokens / 2 sequences, decoder exact; reference $(summ "$tmp/A.json")"

# C: group-size 64 weights (two groups per 64-input matrix)
printf '5 1\n300 0\n17 0\n511 1\n2 0\n' > "$tmp/seqC"
run "$tmp/sim64" "$tmp/C" "$tmp/seqC" "$tmp/w64"
"$PY" golden_decoder.py "$tmp/C" --group 64 --wdir "$tmp/w64" > "$tmp/C.json" || { cat "$tmp/C.json"; echo "FAIL C"; exit 1; }
echo "PASS C: group_size 64, 5 tokens / 2 sequences, decoder exact; reference $(summ "$tmp/C.json")"

# Mutations: the comparison must reject one corrupted value of each kind.
mut() {  # $1 key, $2 field index (1-based after key), $3 label
  "$PY" - "$tmp/A" "$tmp/bad" "$1" "$2" <<'EOF'
import sys
src, dst, key, idx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
out, done = [], False
for line in open(src):
    s = line.split()
    if not done and s and s[0] == key:
        s[idx] = str(int(s[idx]) + 1); line = " ".join(s) + "\n"; done = True
    out.append(line)
assert done, key
open(dst, "w").writelines(out)
EOF
  if "$PY" golden_decoder.py "$tmp/bad" --no-ref > /dev/null 2>&1; then echo "FAIL mutation not detected: $3"; exit 1; fi
}
mut g_slots 1 "x0"; mut g_slots 300 "RMSNorm(res_mix) h0b"; mut g_slots 400 "MoE L0 output"
mut g_slots 900 "L1.out x2"; mut g_sel 2 "MoE selection"; mut g_w 1 "MoE weight"; mut g_r 9 "router logit"
mut g_logit 3 "mix logit"; mut g_p 4 "mix probability"; mut g_e 2 "KDA o_proj exponent"
mut out 7 "KDA output"; mut m_out 13 "MLA output"; mut m_hu 5 "MLA input codes"
mut g_out 5 "res_out mix"; mut g_out 100 "final RMSNorm"; mut h_e 1 "head exponent"; mut h_u 9 "head input codes"
mut h_logits 1 "logit 0"; mut h_logits 400 "logit 399"; mut h_argmax 1 "argmax port"
echo "PASS decoder RTL exactly matches decoder_model.int_step (A, C); 20 mutations rejected"

# B: public prompts 0+1 as one 64-token sequence (full cache), refused token, restart
"$PY" -c "
import nano_ref
a, b = nano_ref.public_tokens(); s = list(a) + list(b)
lines = [f'{t} {int(i == 0)}' for i, t in enumerate(s)] + [f'PROBE {b[2]}', f'{b[0]} 1', f'{b[1]} 0']
open('$tmp/seqB', 'w').write('\n'.join(lines) + '\n')"
run "$tmp/sim128" "$tmp/B" "$tmp/seqB" glue_weights
"$PY" golden_decoder.py "$tmp/B" > "$tmp/B.json" || { cat "$tmp/B.json"; echo "FAIL B"; exit 1; }
echo "PASS B: 64-entry cache + refused token + restart (66 tokens), decoder exact; reference $(summ "$tmp/B.json")"

# D: the official teacher-forced evaluation -- public prompt 0 (48 tokens) and prompt 1
# (16 tokens), each started with seq_start. Headline: per-row logits cosine.
"$PY" -c "
import nano_ref
lines = [f'{t} {int(i == 0)}' for p in nano_ref.public_tokens() for i, t in enumerate(p)]
open('$tmp/seqD', 'w').write('\\n'.join(lines) + '\\n')"
run "$tmp/sim128" "$tmp/D" "$tmp/seqD" glue_weights
"$PY" golden_decoder.py "$tmp/D" > "$tmp/D.json" || { cat "$tmp/D.json"; echo "FAIL D"; exit 1; }
[ -n "${REPORT_DIR:-}" ] && cp "$tmp/B.json" "$tmp/D.json" "$REPORT_DIR/"
echo "PASS D: public prompts 48 + 16 tokens, decoder exact; reference $(summ "$tmp/D.json")"
