#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXP = ROOT / "experiments"
OUT = EXP / "x4" / "harness" / "history_patterns.json"

PATTERNS = [
    ("global_shift_drain_congestion", lambda t: t["x"] == 1 and t["y"] == 1,
     "Global 256-word shift/drain topology failed to converge in routing.", "routing"),
    ("final_extracted_max_capacitance", lambda t: int(t.get("metrics", {}).get("final_max_capacitance_violations", 0) or 0) > 0,
     "Final extracted max-capacitance violations invalidate otherwise clean flows.", "electrical"),
    ("external_sram_boundary", lambda t: t["x"] >= 2 and "sram_macro_usage" in t.get("metrics", {}).get("lint_rules", {}),
     "Behavioral SRAM inference must be rejected at the external hard-macro boundary.", "methodology"),
    ("accumulator_overflow", lambda t: t["x"] >= 2 and "accumulator_overflow" in t.get("metrics", {}).get("lint_rules", {}),
     "Accumulator widths require an executable signed-range proof.", "functional"),
    ("exactly_once_registered_response", lambda t: t["x"] >= 2 and "double_accumulation" in t.get("metrics", {}).get("lint_rules", {}),
     "Every registered SRAM response must have one consume event and one accumulation event.", "functional"),
    ("control_plane_regression", lambda t: t["x"] == 3 and t["y"] in (4, 5),
     "Busy-start, k_dim latching, reset-abort, quiescence, and clean restart need locked regression evidence.", "functional"),
]

def digest(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def inventory(path: Path):
    if not path.exists():
        return {"available": False, "files": [], "note": "raw artifact was not preserved locally by the earlier trial"}
    files = []
    for item in sorted(p for p in path.rglob("*") if p.is_file()):
        files.append({"path": str(item.relative_to(ROOT)), "bytes": item.stat().st_size, "sha256": digest(item)})
    return {"available": True, "file_count": len(files), "files": files}

def main():
    trials = []
    for x in (1, 2, 3):
        p = EXP / f"x{x}" / "trials.jsonl"
        rows = [json.loads(line) for line in p.read_text().splitlines() if line.strip()]
        for row in rows:
            y = row["y"]
            adir = EXP / f"x{x}" / "artifacts" / f"y{y}"
            design = EXP / f"x{x}" / f"DESIGN_Y{y}.md"
            trials.append({
                "x": x, "y": y, "result": row["result"], "trial_path": str(p.relative_to(ROOT)),
                "trial_sha256": digest(p), "design_path": str(design.relative_to(ROOT)),
                "design_sha256": digest(design), "artifact_path": str(adir.relative_to(ROOT)),
                "artifact_inventory": inventory(adir),
                "metrics": row.get("metrics", {}), "bugs_found": row.get("bugs_found", []),
                "learnings": row.get("learnings", "")})
    assert len(trials) == 15, f"expected 15 X1-X3 trials, found {len(trials)}"
    assert {(t['x'], t['y']) for t in trials} == {(x,y) for x in (1,2,3) for y in range(1,6)}
    patterns = []
    for pattern_id, predicate, summary, category in PATTERNS:
        evidence = [{"x": t["x"], "y": t["y"], "result": t["result"],
                     "trial_path": t["trial_path"], "artifact_path": t["artifact_path"]}
                    for t in trials if predicate(t)]
        assert evidence, f"pattern {pattern_id} has no evidence"
        patterns.append({"id": pattern_id, "category": category, "summary": summary, "evidence": evidence})
    disk = EXP / "x3" / "artifacts" / "y5_failed_disk_full"
    marker = EXP / "x3" / "artifacts" / "y4" / "flow_rc"
    assert disk.exists() and (disk / "flow_rc").read_text().strip() == "FLOW_RC=2"
    patterns.extend([
        {"id":"artifact_disk_capacity","category":"infrastructure",
         "summary":"Require sufficient disk before launch and preserve infrastructure failure separately from design outcome.",
         "evidence":[{"x":3,"y":5,"result":"infrastructure_fail_then_clean_retry","artifact_path":str(disk.relative_to(ROOT))}]},
        {"id":"marker_exit_code_integrity","category":"methodology",
         "summary":"A terminal marker must contain a parseable actual pipeline/container exit code; an empty marker is not evidence of success.",
         "evidence":[{"x":3,"y":4,"result":"malformed_marker","artifact_path":str(marker.relative_to(ROOT))}]},
    ])
    payload={"schema_version":1,"source_trial_count":len(trials),"complete_matrix":"X1-X3 15/15",
             "trials":trials,"patterns":patterns}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2)+"\n")
    print(json.dumps({"status":"pass","trials":len(trials),"patterns":len(patterns),"output":str(OUT)}, indent=2))
if __name__ == "__main__": main()
