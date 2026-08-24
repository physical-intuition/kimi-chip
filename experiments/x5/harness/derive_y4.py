#!/usr/bin/env python3
import hashlib, json, re
from pathlib import Path
root=Path('/home/kit/kimi-chip'); x=root/'experiments/x5'; rpt=x/'artifacts/y3_terminal/6_finish.rpt'; met=x/'artifacts/y3_terminal/6_report.json'
t=rpt.read_text(); m=json.loads(met.read_text())
assert 'core_clock period_min = 1.01 fmax = 988.58' in t
assert 'Startpoint: state[1]' in t and 'Endpoint: busy' in t
assert 'Startpoint: product_pipe[140][3]' in t and 'Endpoint: chunk_accum[140][11]' in t
assert m['finish__timing__setup__tns']==0 and m['finish__timing__drv__setup_violation_count']==0
source_target=930.359; source_period=1.074853466; source_fmax=m['finish__timing__fmax__clock:core_clock']/1e6
critical_slack=0.0633; next_internal_slack=0.14
next_internal_period=source_period-next_internal_slack
next_internal_ceiling=1000/next_internal_period
unclamped=source_fmax+0.5*(next_internal_ceiling-source_fmax)
target=min(1000.0,unclamped); period=1000/target
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
p={
 'schema':'x5-y4-y3-slack-derived-policy-v1','source_iteration':'X5-Y3','source_target_mhz':source_target,
 'source_extracted_fmax_mhz':round(source_fmax,3),'source_setup_wns_ns':0.0633,'source_setup_tns_ns':0,
 'observed_critical_path':{'startpoint':'state[1]','endpoint':'busy','slack_ns':critical_slack,'repair':'register busy protocol output instead of combinational state decode'},
 'next_internal_path':{'startpoint':'product_pipe[140][3]','endpoint':'chunk_accum[140][11]','slack_ns':next_internal_slack,'estimated_ceiling_mhz':round(next_internal_ceiling,3)},
 'target_formula':'min(1000, y3_extracted_fmax + 0.5 * (next_internal_estimated_ceiling - y3_extracted_fmax))',
 'unclamped_target_mhz':round(unclamped,3),'derived_target_frequency_mhz':round(target,3),'derived_period_ns':round(period,9),
 'rationale':'Y3 external busy decode limited extracted fmax to 988.581 MHz. Removing it exposes a reg-to-reg MAC-commit path whose measured slack implies about 1069.686 MHz; halfway recovery exceeds 1 GHz, so cap this progressive iteration at 1 GHz.',
 'preserve':['registered request outputs','5-bit request burst budget','registered 8-bit product/MAC pipeline','three-stage hierarchical fold','CAP_MARGIN=50'],
 'provenance':{'finish_report_sha256':sha(rpt),'metrics_sha256':sha(met)}
}
(x/'harness/y4_policy.json').write_text(json.dumps(p,indent=2)+'\n'); print(json.dumps(p,indent=2))
