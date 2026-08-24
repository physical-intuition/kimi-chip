#!/usr/bin/env python3
import hashlib, json
from pathlib import Path
root = Path('/home/kit/kimi-chip')
x5 = root/'experiments/x5'
report = x5/'artifacts/y2_finish.rpt'
metrics = x5/'artifacts/y2_report.json'
x4_trials = [json.loads(x) for x in (root/'experiments/x4/trials.jsonl').read_text().splitlines() if x.strip()]
assert len(x4_trials) == 5
by_y = {r['y']: r for r in x4_trials}
assert round(by_y[1]['metrics']['final_estimated_fmax_mhz'], 3) == 719.140
assert round(by_y[2]['metrics']['final_estimated_fmax_mhz'], 3) == 783.569
text = report.read_text()
m = json.loads(metrics.read_text())
assert 'Startpoint: issued[10]' in text and 'Endpoint: act_req' in text
assert 'wire27208/Z' in text and '357.07' in text
assert round(m['finish__timing__fmax__clock:core_clock']/1e6, 3) == 890.470
historical_gain = by_y[2]['metrics']['final_estimated_fmax_mhz']/by_y[1]['metrics']['final_estimated_fmax_mhz'] - 1.0
recovery_fraction = 0.50
target = (m['finish__timing__fmax__clock:core_clock']/1e6) * (1.0 + recovery_fraction * historical_gain)
period = 1000.0/target
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
policy = {
  'schema':'x5-y3-combined-evidence-policy-v1',
  'source_iteration':'X5-Y2',
  'source_fmax_mhz':round(m['finish__timing__fmax__clock:core_clock']/1e6, 3),
  'source_setup_wns_ns':-0.06,
  'source_setup_tns_ns':m['finish__timing__setup__tns'],
  'source_setup_violations':m['finish__timing__drv__setup_violation_count'],
  'source_hold_violations':m['finish__timing__drv__hold_violation_count'],
  'combined_repairs':[
    {'evidence':'X5-Y2 MAC pipeline removed act_rdata->chunk_accum from max setup paths', 'preserve':'registered 8-bit product and overlapped response/product/MAC valid pipeline'},
    {'evidence':'X5-Y2 worst max path is issued[10] through request decode to act_req at -0.06 ns', 'repair':'drive request outputs from request_active/request_addr registers; use a 5-bit chunk-local request counter'},
    {'evidence':'X5-Y2 max-cap failures wire27208/Z 357.07/242.31 and wire27209/Z 282.15/242.31', 'repair':'raise CAP_MARGIN from 30 to 50 for earlier stronger buffering'},
  ],
  'historical_request_comparator_removal_gain_ratio':round(historical_gain, 9),
  'conservative_recovery_fraction':recovery_fraction,
  'target_formula':'x5_y2_fmax * (1 + 0.50 * (x4_y2_fmax/x4_y1_fmax - 1))',
  'derived_target_frequency_mhz':round(target, 3),
  'derived_period_ns':round(period, 9),
  'provenance':{
    'x5_y2_finish_report':{'path':str(report.relative_to(root)), 'sha256':sha(report)},
    'x5_y2_metrics':{'path':str(metrics.relative_to(root)), 'sha256':sha(metrics)},
    'x4_trials':{'path':'experiments/x4/trials.jsonl','sha256':sha(root/'experiments/x4/trials.jsonl')},
  }
}
(x5/'harness/y3_policy.json').write_text(json.dumps(policy,indent=2)+'\n')
print(json.dumps(policy,indent=2))
