#!/usr/bin/env python3
import json
from pathlib import Path
root = Path('/home/kit/kimi-chip/experiments/x5')
rtl = (root/'rtl/x5_y2_kimi.v').read_text()
policy = json.loads((root/'harness/y2_policy.json').read_text())
checks = {
    'y1_terminal_evidence_ingested': policy['source_extracted_fmax_mhz'] == 911.455 and policy['source_setup_wns_ns'] < 0,
    'target_held_at_y1_goal': policy['target_frequency_mhz'] == 937.092,
    'observed_path_named': policy['worst_path']['startpoint'] == 'act_rdata[28]' and policy['worst_path']['endpoint'] == 'chunk_accum[121][11]',
    'product_is_registered_8bit': 'reg signed [7:0] product_pipe [0:15][0:15];' in rtl,
    'response_valid_stage': 'response_valid <= request_fire;' in rtl,
    'product_valid_stage': 'product_valid <= response_valid;' in rtl,
    'mac_commit_stage': 'wire commit_fire = (state == S_RUN) && product_valid;' in rtl,
    'request_and_commit_overlap': 'if (request_fire)' in rtl and 'if (commit_fire)' in rtl,
    'request_not_serialized_by_mac': "localparam S_ACCUM" not in rtl and "localparam S_REQ" not in rtl,
    'chunk_boundary_backpressure': "chunk_issued < 5'd16" in rtl,
    'signed_product_extension': '{{4{product_pipe[gr][gc][7]}}, product_pipe[gr][gc]}' in rtl,
    'inherited_three_stage_fold': all(x in rtl for x in ['S_FOLD_LO0', 'S_FOLD_LO1', 'S_FOLD_HI', 'fold_carry6', 'fold_carry12']),
    'no_y3_preplan': not (root/'rtl/x5_y3_kimi.v').exists(),
}
failed = [k for k,v in checks.items() if not v]
out = {'status': 'pass' if not failed else 'fail', 'checks': checks, 'failed': failed, 'target_mhz': policy['target_frequency_mhz']}
(root/'build/lint_y2.json').write_text(json.dumps(out, indent=2)+'\n')
print(json.dumps(out, indent=2))
if failed: raise SystemExit(1)
