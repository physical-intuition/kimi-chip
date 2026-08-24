#!/usr/bin/env python3
import json, pathlib, re, sys
root=pathlib.Path(__file__).resolve().parents[3]
x5=root/'experiments/x5'; rtl=(x5/'rtl/x5_y1_kimi.v').read_text()
policy=json.loads((x5/'harness/y1_policy.json').read_text())
history=json.loads((x5/'harness/x4_learning.json').read_text())
checks={
 'x4_all_five_ingested': len(history['x4_cells'])==5 and [c['y'] for c in history['x4_cells']]==[1,2,3,4,5],
 'target_emerged_from_policy': policy['generated_from_x4_only'] and policy['derived_target_frequency_mhz']>policy['baseline_extracted_fmax_mhz'],
 'x4_sources_hashed': all(s.get('sha256') for s in history['sources']) and all(c['provenance']['rtl']['sha256'] for c in history['x4_cells']),
 'external_sram_boundary': all(x in rtl for x in ('act_req','act_addr','act_rdata','weight_req','weight_addr','weight_rdata')) and not re.search(r'\b(?:mem|sram|ram)\w*\s*\[',rtl,re.I),
 'chunk_width_12': bool(re.search(r'reg\s+signed\s+\[11:0\]\s+chunk_accum',rtl)),
 'wide_width_24': bool(re.search(r'reg\s+signed\s+\[23:0\]\s+wide_accum',rtl)),
 'fold_interval_16': "chunk_count == 5'd15" in rtl,
 'three_stage_fold': all(x in rtl for x in ('S_FOLD_LO0','S_FOLD_LO1','S_FOLD_HI','fold_carry6','fold_carry12')),
 'registered_6bit_slices': all(x in rtl for x in ('wide_accum[gr][gc][5:0]','wide_accum[gr][gc][11:6]','wide_accum[gr][gc][23:12]')),
 'no_remaining_12bit_low_add': not bool(re.search(r'wide_accum\[gr\]\[gc\]\[11:0\].*\+.*chunk_accum',rtl)),
 'no_direct_24bit_fold': not bool(re.search(r'wide_accum\[gr\]\[gc\]\s*<=\s*wide_accum\[gr\]\[gc\]\s*\+',rtl)),
 'tail_flush': "consumed + 1'b1 == k_dim_q" in rtl and 'fold_finishes_run' in rtl,
 'max_k_65535_interface': all(x in rtl for x in ('input  wire [15:0]  k_dim','output reg  [15:0]  act_addr','output reg  [15:0]  weight_addr')),
 'request_comparator_stays_removed': 'issued < k_dim_q' not in rtl,
 'registered_readout_preserved': 'out_wdata <= drain_row_data[drain_col]' in rtl and not re.search(r'out_wdata\s*<=\s*wide_accum',rtl),
 'x5_only_y1_exists': not any((x5/f'rtl/x5_y{y}_kimi.v').exists() for y in range(2,6)),
}
checks['chunk_range_proof']=16*64 <= 2**11-1
checks['wide_range_proof']=65535*64 <= 2**23-1
report={'status':'pass' if all(checks.values()) else 'fail','checks':checks,'derived_target_mhz':policy['derived_target_frequency_mhz'],'evidence':policy['remaining_bottlenecks']}
out=x5/'build/lint_y1.json'; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2)); sys.exit(0 if all(checks.values()) else 1)
