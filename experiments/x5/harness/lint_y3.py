#!/usr/bin/env python3
import json
from pathlib import Path
x=Path('/home/kit/kimi-chip/experiments/x5')
rtl=(x/'rtl/x5_y3_kimi.v').read_text(); cfg=(x/'flow/config_y3.mk').read_text(); p=json.load(open(x/'harness/y3_policy.json'))
checks={
 'y2_terminal_evidence': p['source_fmax_mhz']==890.47 and p['source_setup_wns_ns']==-0.06,
 'target_derived_above_930': 930 < p['derived_target_frequency_mhz'] < 937.092,
 'mac_pipeline_preserved': all(s in rtl for s in ['reg signed [7:0] product_pipe','response_valid','product_valid','commit_fire']),
 'overlap_preserved': 'wire request_fire' in rtl and 'wire commit_fire' in rtl and 'S_RUN' in rtl,
 'wide_request_comparator_removed': 'issued < k_dim_q' not in rtl and '(chunk_issued <' not in rtl,
 'request_outputs_registered': 'act_req = request_active;' in rtl and 'act_addr = request_addr;' in rtl,
 'local_five_bit_budget': 'reg [4:0] requests_left;' in rtl and "requests_left == 5'd1" in rtl,
 'fixed_16_request_backpressure': "requests_left <= (k_dim >= 16) ? 5'd16" in rtl,
 'three_stage_fold_preserved': all(s in rtl for s in ['S_FOLD_LO0','S_FOLD_LO1','S_FOLD_HI','fold_carry6','fold_carry12']),
 'cap_margin_repair': 'CAP_MARGIN = 50' in cfg,
 'source_hashes_recorded': all(v.get('sha256') for v in p['provenance'].values()),
 'no_y4_preplan': not (x/'rtl/x5_y4_kimi.v').exists(),
}
failed=[k for k,v in checks.items() if not v]
out={'status':'pass' if not failed else 'fail','checks':checks,'failed':failed,'derived_target_mhz':p['derived_target_frequency_mhz']}
(x/'build/lint_y3.json').write_text(json.dumps(out,indent=2)+'\n'); print(json.dumps(out,indent=2))
if failed: raise SystemExit(1)
