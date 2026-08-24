#!/usr/bin/env python3
import argparse
import json
import math
import pathlib
import re
import sys


def fail(rule, message, failures):
    failures.append({"rule": rule, "status": "fail", "message": message})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    root = pathlib.Path(__file__).resolve().parents[3]
    policy = json.loads(pathlib.Path(args.policy).read_text())
    texts = []
    for rel in policy["rtl_files"]:
        path = root / rel
        if not path.is_file():
            raise SystemExit(f"missing RTL: {path}")
        texts.append(path.read_text())
    rtl = "\n".join(texts)
    results = []
    failures = []

    storage = policy["storage"]
    if storage["mode"] != "external_macro_interface":
        fail("sram_macro_usage", "storage mode must be external_macro_interface or a hard macro", failures)
    missing = [p for p in storage["required_port_fragments"] if not re.search(rf"\b{re.escape(p)}\b", rtl)]
    behavioral = re.findall(r"\breg\s*(?:signed\s*)?(?:\[[^;]+?\]\s*)?([A-Za-z_]\w*(?:mem|sram|ram)\w*)\s*\[", rtl, re.I)
    if missing:
        fail("sram_macro_usage", f"missing external SRAM boundary ports: {missing}", failures)
    elif behavioral:
        fail("sram_macro_usage", f"behavioral SRAM-like arrays are forbidden: {behavioral}", failures)
    else:
        results.append({"rule": "sram_macro_usage", "status": "pass", "message": "external SRAM macro boundary is explicit; no behavioral SRAM array inferred"})

    arith = policy["arithmetic"]
    lane_min = -(1 << (arith["lane_width"] - 1))
    lane_max = (1 << (arith["lane_width"] - 1)) - 1
    products = [lane_min * lane_min, lane_min * lane_max, lane_max * lane_min, lane_max * lane_max]
    min_sum = min(products) * arith["max_k"]
    max_sum = max(products) * arith["max_k"]
    required = 1
    while min_sum < -(1 << (required - 1)) or max_sum > (1 << (required - 1)) - 1:
        required += 1
    declared = arith["accumulator_width"]
    width_literal = re.search(r"reg\s+signed\s+\[(\d+)\s*:\s*0\]\s+accum_bank", rtl)
    actual = int(width_literal.group(1)) + 1 if width_literal else None
    if declared < required or actual != declared:
        fail("accumulator_overflow", f"required={required}, policy={declared}, RTL={actual}, sum_range=[{min_sum},{max_sum}]", failures)
    else:
        results.append({"rule": "accumulator_overflow", "status": "pass", "message": f"{declared}-bit signed accumulator covers [{min_sum},{max_sum}], minimum {required} bits"})

    control = policy["response_control"]
    required_patterns = [control["valid_signal"], control["accumulation_guard"], control["issue_guard"], control["consume_counter"]]
    absent = [pattern for pattern in required_patterns if pattern not in rtl]
    updates = len(re.findall(r"accum_bank\s*\[[^\]]+\]\s*\[[^\]]+\]\s*<=\s*accum_bank", rtl))
    if absent or updates != 1:
        fail("double_accumulation", f"missing control patterns={absent}; accumulation update sites={updates}", failures)
    else:
        results.append({"rule": "double_accumulation", "status": "pass", "message": "single accumulation site is gated by one-cycle response valid and consume tracking"})

    payload = {"status": "fail" if failures else "pass", "policy": str(pathlib.Path(args.policy)), "results": results + failures}
    report = pathlib.Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
