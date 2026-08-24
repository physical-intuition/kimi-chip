#!/usr/bin/env python3
import difflib, hashlib, json, math, re
from pathlib import Path

ROOT = Path('/home/kit/kimi-chip')
X4 = ROOT / 'experiments/x4'
X5 = ROOT / 'experiments/x5'
OUT = X5 / 'harness'
OUT.mkdir(parents=True, exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def rel(path):
    return str(path.relative_to(ROOT))

def source(path):
    assert path.is_file(), path
    return {'path': rel(path), 'sha256': sha(path)}

trials_path = X4 / 'trials.jsonl'
trials = [json.loads(line) for line in trials_path.read_text().splitlines() if line.strip()]
assert [t['y'] for t in trials] == [1,2,3,4,5]
assert all(t['x'] == 4 for t in trials)

expected = {1: (719.14, 'fail'), 2: (783.569, 'pass'), 3: (837.683, 'pass'), 4: (900.93, 'fail'), 5: (909.621, 'pass')}
records=[]
for t in trials:
    y=t['y']; m=t['metrics']; f=float(m['final_estimated_fmax_mhz'])
    assert abs(f-expected[y][0]) < 0.002 and t['result']==expected[y][1]
    timing=X4/f'artifacts/y{y}/timing_analysis.json'
    rtl=X4/f'rtl/x4_y{y}_kimi.v'
    design=X4/f'DESIGN_Y{y}.md'
    evidence=json.loads(timing.read_text())
    assert abs(float(evidence['achieved_extracted_fmax_mhz'])-f) < 0.002
    diff=''
    diff_sources=[]
    if y>1:
        prev=X4/f'rtl/x4_y{y-1}_kimi.v'
        diff=''.join(difflib.unified_diff(prev.read_text().splitlines(True),rtl.read_text().splitlines(True),fromfile=rel(prev),tofile=rel(rtl)))
        diff_sources=[source(prev),source(rtl)]
    records.append({
      'y':y,'result':t['result'],'target_mhz':m['frequency_constraint_mhz'],
      'extracted_fmax_mhz':f,'gain_from_previous_mhz': None if y==1 else round(f-records[-1]['extracted_fmax_mhz'],3),
      'goal':t['goal'],'rtl_change':m.get('rtl_change'),'physical_design_change':m.get('physical_design_change'),
      'bugs_found':t['bugs_found'],'learnings':t['learnings'],
      'worst_startpoint':m['worst_startpoint'],'worst_endpoint':m['worst_endpoint'],
      'setup_wns_ns':m['final_setup_worst_slack_ns'],'max_cap_violations':m['final_max_capacitance_violations'],
      'provenance':{'trial':source(trials_path),'timing':source(timing),'design':source(design),'rtl':source(rtl),'rtl_diff_sources':diff_sources},
      'rtl_diff':diff
    })

# Verify the causal changes from evidence and actual RTL/config differences.
assert 'issued < k_dim_q' in (X4/'rtl/x4_y1_kimi.v').read_text()
assert 'issued < k_dim_q' not in (X4/'rtl/x4_y2_kimi.v').read_text()
assert 'drain_row_data' not in (X4/'rtl/x4_y2_kimi.v').read_text()
assert 'drain_row_data' in (X4/'rtl/x4_y3_kimi.v').read_text()
assert 'S_FOLD_LO' not in (X4/'rtl/x4_y3_kimi.v').read_text()
assert 'S_FOLD_LO' in (X4/'rtl/x4_y4_kimi.v').read_text()
assert (X4/'rtl/x4_y4_kimi.v').read_text().replace('x4_y4_kimi','x4_y5_kimi').split('module')[1] == (X4/'rtl/x4_y5_kimi.v').read_text().split('module')[1]
assert 'CAP_MARGIN = 22' in (X4/'flow/config_y4.mk').read_text()
assert 'CAP_MARGIN = 30' in (X4/'flow/config_y5.mk').read_text()

report=X4/'artifacts/y5/reports/6_finish.rpt'
text=report.read_text(errors='replace')
path_re=re.compile(r'Startpoint: ([^\n]+).*?Endpoint: ([^\n]+).*?Path Type: max.*?\n\s*(-?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)',re.S)
paths=[]
for s,e,sl in path_re.findall(text):
    item={'startpoint':s.strip(),'endpoint':e.strip(),'slack_ns':float(sl)}
    if item not in paths: paths.append(item)
setup_bottlenecks=[p for p in paths if 'chunk_accum' in p['startpoint'] and 'wide_accum' in p['endpoint']]
assert setup_bottlenecks

base=records[-1]['extracted_fmax_mhz']
period=float(trials[-1]['metrics']['clock_constraint_ns'])
# X4-Y4's report-driven 24-to-12-bit fold split gives an empirical estimate
# for the value of halving the remaining 12-bit low-slice carry chain. X5-Y1
# takes only 40% of that measured relative gain as a conservative first target.
prior_fold_gain_ratio=records[3]['extracted_fmax_mhz']/records[2]['extracted_fmax_mhz']-1.0
conservative_fraction=0.40
target=round(base*(1.0+conservative_fraction*prior_fold_gain_ratio),3)
assert target > base

history={'schema':'x5-x4-evidence-v1','sources':[source(trials_path),source(X4/'X4_SUMMARY.md'),source(report)],'x4_cells':records}
policy={
 'schema':'x5-y1-derived-policy-v1',
 'generated_from_x4_only':True,
 'baseline_extracted_fmax_mhz':base,
 'observed_top_setup_paths':paths,
 'remaining_bottlenecks':[
   {'cone':'registered chunk_accum to low wide_accum fold','evidence':'X4-Y5 worst max setup path has 19 combinational cells from chunk_accum[156][1] to wide_accum[156][11]','repair':'split the remaining low 12-bit fold addition into registered 6-bit slices'}],
 'objective':'push_frequency_beyond_x4',
 'prior_report_proven_fold_split_gain_ratio':round(prior_fold_gain_ratio,9),
 'conservative_gain_fraction':conservative_fraction,
 'target_formula':'x4_y5_extracted_fmax * (1 + 0.40 * (x4_y4_fmax / x4_y3_fmax - 1))',
 'derived_target_frequency_mhz':target,
 'derived_period_ns':round(1000.0/target,9),
 'allowed_rtl_change':'split the remaining 12-bit low fold addition into registered low/high 6-bit updates; preserve all prior X4 repairs',
 'provenance':{'final_report':source(report),'y5_timing':source(X4/'artifacts/y5/timing_analysis.json'),'y5_rtl':source(X4/'rtl/x4_y5_kimi.v')}
}
(OUT/'x4_learning.json').write_text(json.dumps(history,indent=2)+'\n')
(OUT/'y1_policy.json').write_text(json.dumps(policy,indent=2)+'\n')
print(json.dumps({'records':len(records),'max_setup_paths':paths,'prior_fold_gain_ratio':prior_fold_gain_ratio,'derived_target_mhz':target},indent=2))
