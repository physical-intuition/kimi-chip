#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


def number(text, pattern, cast=float, default=None):
    m = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
    return cast(m.group(1)) if m else default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifact-dir", required=True)
    ap.add_argument("--target-mhz", required=True, type=float)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    root = Path(args.artifact_dir)
    finish_path = root / "reports/6_finish.rpt"
    metrics_path = root / "logs/6_report.json"
    route_path = root / "logs/5_2_route.log"
    drc_path = root / "reports/5_route_drc.rpt"
    antenna_path = root / "reports/drt_antennas.log"
    for p in (finish_path, metrics_path, route_path, drc_path, antenna_path):
        if not p.is_file():
            raise SystemExit(f"missing required raw report: {p}")
    finish = finish_path.read_text(errors="replace")
    metrics = json.loads(metrics_path.read_text())
    route = route_path.read_text(errors="replace")
    drc = drc_path.read_text(errors="replace")
    antenna = antenna_path.read_text(errors="replace")

    max_section = re.search(
        r"finish report_checks -path_delay max(.*?)(?=\n=+\nfinish report_checks -unconstrained)",
        finish,
        re.DOTALL,
    )
    max_report = max_section.group(1) if max_section else ""
    path_blocks = re.findall(r"(Startpoint:.*?slack \((?:MET|VIOLATED)\))", max_report, re.DOTALL)
    def path_slack(block):
        matches = re.findall(r"^\s*(-?[0-9.]+)\s+slack \((?:MET|VIOLATED)\)", block, re.MULTILINE)
        return float(matches[-1]) if matches else float("inf")
    worst_path = min(path_blocks, key=path_slack) if path_blocks else ""
    pin_cells = re.findall(
        r"\^?\s*([A-Za-z0-9_$.[\]-]+)/[A-Z0-9]+\s+\(([A-Z][A-Z0-9_]*_X[0-9]+|DFF[A-Z0-9_]*)\)\s*$",
        worst_path,
        re.MULTILINE,
    )
    path_instances = []
    for instance, cell in pin_cells:
        if not path_instances or path_instances[-1][0] != instance:
            path_instances.append((instance, cell))
    cells = [cell for _, cell in path_instances]
    comb_cells = [c for c in cells if not re.search(r"DFF|CLKBUF", c, re.I)]
    fanouts = [int(v) for v in re.findall(r"^\s*(\d+)\s+[0-9.]+\s+[0-9.]+\s+[0-9.]+\s+[0-9.]+\s+[\^v]", worst_path, re.MULTILINE)]
    route_initial = number(route, r"(?:initial|Number of violations)\D+(\d+)", int)
    route_iters = len(re.findall(r"(?:optimization|repair).*iteration", route, re.I))
    antenna_nets = number(antenna, r"Number of violating nets:\s*(\d+)", int, 0)
    antenna_pins = number(antenna, r"Number of violating pins:\s*(\d+)", int, 0)
    drc_count = len([line for line in drc.splitlines() if line.strip() and not line.lstrip().startswith("#")])

    key = lambda name, default=None: metrics.get(name, default)
    setup_ws = key("finish__timing__setup__ws")
    hold_ws = key("finish__timing__hold__ws")
    fmax_hz = key("finish__timing__fmax")
    payload = {
        "target_frequency_mhz": args.target_mhz,
        "target_period_ns": 1000.0 / args.target_mhz,
        "achieved_extracted_fmax_mhz": fmax_hz / 1e6 if fmax_hz is not None else None,
        "target_met": setup_ws is not None and setup_ws >= 0,
        "timing": {
            "setup_wns_ns": setup_ws,
            "setup_tns_ns": key("finish__timing__setup__tns"),
            "hold_wns_ns": hold_ws,
            "hold_tns_ns": key("finish__timing__hold__tns"),
            "setup_violating_endpoints": key("finish__timing__drv__setup_violation_count"),
            "hold_violating_endpoints": key("finish__timing__drv__hold_violation_count"),
            "worst_startpoint": number(worst_path, r"Startpoint:\s*(\S+)", str),
            "worst_endpoint": number(worst_path, r"Endpoint:\s*(\S+)", str),
            "path_group": number(worst_path, r"Path Group:\s*(\S+)", str),
            "path_instances": [{"instance": instance, "cell": cell} for instance, cell in path_instances],
            "path_cells": cells,
            "combinational_cells": comb_cells,
            "combinational_depth": len(comb_cells),
            "max_path_fanout": max(fanouts) if fanouts else None,
            "worst_path_raw": worst_path
        },
        "electrical": {
            "max_slew_violations": key("finish__timing__drv__max_slew"),
            "max_fanout_violations": key("finish__timing__drv__max_fanout"),
            "max_capacitance_violations": key("finish__timing__drv__max_cap")
        },
        "routing": {
            "initial_detailed_route_violations": route_initial,
            "repair_iteration_mentions": route_iters,
            "final_drc_violations": drc_count,
            "antenna_net_violations": antenna_nets,
            "antenna_pin_violations": antenna_pins
        },
        "hold_repair_side_effects": {
            "timing_repair_buffer_count": key("finish__design__instance__count__class:timing_repair_buffer"),
            "hold_clean": hold_ws is not None and hold_ws >= 0 and key("finish__timing__drv__hold_violation_count") == 0
        },
        "raw_evidence": {
            "final_timing": str(finish_path),
            "final_metrics": str(metrics_path),
            "detailed_route_log": str(route_path),
            "drc_report": str(drc_path),
            "antenna_report": str(antenna_path)
        }
    }
    strict = payload["target_met"] and all(v == 0 for v in (
        payload["timing"]["setup_violating_endpoints"], payload["timing"]["hold_violating_endpoints"],
        payload["electrical"]["max_slew_violations"], payload["electrical"]["max_fanout_violations"],
        payload["electrical"]["max_capacitance_violations"], payload["routing"]["final_drc_violations"],
        payload["routing"]["antenna_net_violations"], payload["routing"]["antenna_pin_violations"]))
    payload["strict_physical_pass"] = strict
    Path(args.output).write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
