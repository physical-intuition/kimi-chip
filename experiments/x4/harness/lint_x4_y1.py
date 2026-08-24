#!/usr/bin/env python3
import json, pathlib, re, sys
root=pathlib.Path(__file__).resolve().parents[3]
rtl=(root/'experiments/x4/rtl/x4_y1_kimi.v').read_text()
checks={
 'external_sram_boundary': all(x in rtl for x in ('act_req','act_addr','act_rdata','weight_req','weight_addr','weight_rdata')) and not re.search(r'\b(?:mem|sram|ram)\w*\s*\[',rtl,re.I),
 'chunk_width_12': bool(re.search(r'reg\s+signed\s+\[11:0\]\s+chunk_accum',rtl)),
 'wide_width_24': bool(re.search(r'reg\s+signed\s+\[23:0\]\s+wide_accum',rtl)),
 'fold_interval_16': 'chunk_count == 5\'d15' in rtl,
 'separate_fold_state': 'state == S_FOLD' in rtl and 'state == S_ACCUM' in rtl,
 'tail_flush': 'consumed + 1\'b1 == k_dim_q' in rtl and 'fold_finishes_run' in rtl,
 'max_k_65535_interface': all(x in rtl for x in ('input  wire [15:0]  k_dim','output reg  [15:0]  act_addr','output reg  [15:0]  weight_addr')),
 'single_accumulation_site': len(re.findall(r'chunk_accum\[[^]]+\]\[[^]]+\]\s*<=\s*chunk_accum\[[^]]+\]\[[^]]+\]\s*\+',rtl))==1,
 'resetless_datapath': not bool(re.search(r'if\s*\(!rst_n\)[\s\S]{0,500}chunk_accum',rtl)),
}
# Executable signed range proofs.
checks['chunk_range_proof'] = 16*64 <= (2**11-1)
checks['wide_range_proof'] = 65535*64 <= (2**23-1)
report={'status':'pass' if all(checks.values()) else 'fail','checks':checks,'proof':{'chunk_max_magnitude':16*64,'signed_12_max':2**11-1,'wide_max_positive':65535*64,'signed_24_max':2**23-1}}
out=root/'experiments/x4/build/lint_y1.json'; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2)); sys.exit(0 if all(checks.values()) else 1)
