#!/usr/bin/env python3
import json
from pathlib import Path
x=Path('/home/kit/kimi-chip/experiments/x5'); rtl=(x/'rtl/x5_y4_kimi.v').read_text(); cfg=(x/'flow/config_y4.mk').read_text(); sdc=(x/'flow/constraint_y4.sdc').read_text(); p=json.load(open(x/'harness/y4_policy.json'))
checks={
'y3_terminal_pass_ingested':p['source_extracted_fmax_mhz']==988.581 and p['source_setup_tns_ns']==0,
'target_derived_1ghz':p['derived_target_frequency_mhz']==1000 and p['unclamped_target_mhz']>1000,
'critical_path_named':p['observed_critical_path']['endpoint']=='busy',
'next_internal_path_named':p['next_internal_path']['endpoint']=='chunk_accum[140][11]',
'busy_registered':'output reg          busy' in rtl and 'assign busy' not in rtl and "busy <= 1'b1" in rtl and "busy <= 1'b0" in rtl,
'mac_pipeline_preserved':all(s in rtl for s in ['reg signed [7:0] product_pipe','response_valid','product_valid','commit_fire']),
'request_fix_preserved':'act_req = request_active;' in rtl and 'reg [4:0] requests_left;' in rtl and 'issued < k_dim_q' not in rtl,
'fold_preserved':all(s in rtl for s in ['S_FOLD_LO0','S_FOLD_LO1','S_FOLD_HI']),
'cap_margin_preserved':'CAP_MARGIN = 50' in cfg,
'physical_target':'ABC_CLOCK_PERIOD_IN_PS = 1000' in cfg and 'set clk_period 1.000000000' in sdc,
'provenance_hashes':all(p['provenance'].values()),
'no_y5_preplan':not (x/'rtl/x5_y5_kimi.v').exists(),
}
failed=[k for k,v in checks.items() if not v]; out={'status':'pass' if not failed else 'fail','checks':checks,'failed':failed,'target_mhz':1000.0}; (x/'build/lint_y4.json').write_text(json.dumps(out,indent=2)+'\n'); print(json.dumps(out,indent=2)); raise SystemExit(bool(failed))
