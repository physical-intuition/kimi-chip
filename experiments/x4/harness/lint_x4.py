#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def has(pattern, text):
    return re.search(pattern, text, re.MULTILINE | re.DOTALL) is not None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    policy_path = Path(args.policy)
    policy = json.loads(policy_path.read_text())
    rtl = "\n".join((ROOT / p).read_text() for p in policy["rtl_files"])
    tb = "\n".join((ROOT / p).read_text() for p in policy["testbench_files"])
    flow = "\n".join((ROOT / p).read_text() for p in policy["flow_files"])
    launch = "\n".join((ROOT / p).read_text() for p in policy["launch_files"])
    history = json.loads((ROOT / policy["history_patterns"]).read_text())
    known = {p["id"] for p in history["patterns"]}
    results = []

    def check(rule, condition, message):
        evidence = policy["rules"][rule]["evidence_pattern_ids"]
        missing = sorted(set(evidence) - known)
        ok = condition and not missing
        results.append({"rule": rule, "status": "pass" if ok else "fail",
                        "message": message if ok else f"check failed; missing evidence={missing}",
                        "evidence_pattern_ids": evidence,
                        "executable_check": policy["rules"][rule]["executable_check"]})

    check("localized_stationary_drain",
          "wide_accum" in rtl and "drain_row" in rtl and "drain_col" in rtl and
          not has(r"wide_accum\s*\[[^]]+\]\s*\[[^]]+\]\s*<=\s*wide_accum\s*\[[^]]+\]\s*\[[^]]+\s*[+-]", rtl),
          "stationary row/column-indexed drain; no global accumulator shift")
    margin = re.search(r"CAP_MARGIN\s*=\s*(\d+)", flow)
    check("strict_extracted_electrical",
          margin is not None and int(margin.group(1)) >= 21 and "parse_timing.py" in policy["postroute_parser"],
          f"CAP_MARGIN={margin.group(1) if margin else 'missing'} and strict final extracted parser required")
    behavioral = has(r"\breg\s+(?:signed\s+)?(?:\[[^;]+?\]\s*)?[A-Za-z_]\w*(?:mem|sram|ram)\w*\s*\[", rtl)
    ports = all(p in rtl for p in ("act_req", "act_addr", "act_rdata", "weight_req", "weight_addr", "weight_rdata"))
    check("external_sram_boundary", ports and not behavioral,
          "external registered SRAM interface present; no behavioral SRAM-like array")
    widths = has(r"reg\s+signed\s*\[11:0\]\s+chunk_accum", rtl) and has(r"reg\s+signed\s*\[23:0\]\s+wide_accum", rtl)
    fold16 = "chunk_count == 5'd15" in rtl
    check("hierarchical_width_proof", widths and fold16 and all(k in tb for k in ("run_case(15)", "run_case(16)", "run_case(17)", "run_case(65535)")),
          "signed 12-bit chunks fold every 16 adds into signed 24-bit state; boundary and max-K regressions present")
    update_sites = len(re.findall(r"chunk_accum\s*\[[^]]+\]\s*\[[^]]+\]\s*<=\s*chunk_accum", rtl))
    separate_fold = "state == S_ACCUM" in rtl and "state == S_FOLD" in rtl
    check("exactly_once_registered_response", update_sites == 1 and separate_fold and "act_req !== weight_req" in tb,
          "one product accumulation site, paired requests, and disjoint ACCUM/FOLD cycles")
    controls = all(s in tb for s in policy["required_regression_fragments"])
    check("control_plane_regression", controls and "k_dim_q <= k_dim" in rtl and "if (state == S_IDLE && start)" in rtl,
          "latched k_dim plus reset/restart, busy-start, signed-extrema, and tail-flush regression fragments present")
    check("disk_preflight", "df -Pk" in launch and "MIN_FREE_KB" in launch,
          "remote launch refuses insufficient free disk before ORFS")
    check("marker_exit_integrity", "PIPESTATUS[0]" in launch and "FLOW_RC=%s" in launch,
          "launch captures Docker pipeline exit code and writes a parseable FLOW_RC marker")

    payload = {"status": "pass" if all(r["status"] == "pass" for r in results) else "fail",
               "policy": str(policy_path), "history_pattern_count": len(known), "results": results}
    report = Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))
    return 0 if payload["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
