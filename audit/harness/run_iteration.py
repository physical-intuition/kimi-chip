#!/usr/bin/env python3
"""
Harness v2: Run synthesis/P&R iterations with automatic analysis.

Usage:
    python run_iteration.py --x 1 --y 1
    python run_iteration.py --auto  # auto-increment from last trial
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from config import (
    HARNESS_CONFIG, HARNESS_DIR, AUDIT_DIR, RTL_DIR, 
    FLOW_DIR, GOALS_DIR, TRIALS_FILE, MODEL_CONFIG
)
from scoring import score_iteration, classify_critical_path, get_suggestions


def load_trials() -> list:
    """Load all trials from jsonl."""
    trials = []
    if Path(TRIALS_FILE).exists():
        with open(TRIALS_FILE) as f:
            for line in f:
                if line.strip():
                    trials.append(json.loads(line))
    return trials


def save_trial(trial: dict):
    """Append a trial to jsonl."""
    with open(TRIALS_FILE, "a") as f:
        f.write(json.dumps(trial) + "\n")


def get_last_trial() -> dict:
    """Get most recent trial."""
    trials = load_trials()
    return trials[-1] if trials else None


def detect_plateau(trials: list, threshold: float, count: int) -> bool:
    """Check if last N trials are within threshold of each other."""
    if len(trials) < count:
        return False
    
    recent = trials[-count:]
    freqs = [t.get("freq_mhz", 0) for t in recent if t.get("freq_mhz")]
    if len(freqs) < count:
        return False
    
    max_freq = max(freqs)
    min_freq = min(freqs)
    if max_freq == 0:
        return False
    
    return (max_freq - min_freq) / max_freq < threshold


def get_next_xy(trials: list) -> tuple:
    """Determine next X.Y based on trials and plateau detection."""
    if not trials:
        return 1, 1
    
    last = trials[-1]
    x, y = last.get("x", 1), last.get("y", 1)
    
    # Check for plateau
    x_trials = [t for t in trials if t.get("x") == x]
    if detect_plateau(x_trials, 
                      HARNESS_CONFIG["plateau_threshold"],
                      HARNESS_CONFIG["plateau_count"]):
        print(f"[PLATEAU] Detected plateau at X{x}, bumping to X{x+1}")
        return x + 1, 1
    
    # Check max Y
    if y >= HARNESS_CONFIG["max_y_per_x"]:
        print(f"[MAX_Y] Reached max Y={y} for X{x}, bumping to X{x+1}")
        return x + 1, 1
    
    return x, y + 1


def load_goal(x: int, y: int) -> str:
    """Load goal file for iteration."""
    goal_file = os.path.join(GOALS_DIR, f"x{x}_y{y}.txt")
    if Path(goal_file).exists():
        with open(goal_file) as f:
            return f.read().strip()
    return f"No goal file found at {goal_file}"


def save_goal(x: int, y: int, goal: str):
    """Save goal file for iteration."""
    goal_file = os.path.join(GOALS_DIR, f"x{x}_y{y}.txt")
    with open(goal_file, "w") as f:
        f.write(goal)


def get_rtl_files(x: int, y: int) -> list:
    """Get RTL files for this iteration."""
    # For now, always use audit/rtl baseline
    # Future: rtl_gen/ can produce modified RTL per iteration
    rtl_files = list(Path(RTL_DIR).glob("*.v"))
    return [str(f) for f in rtl_files]


def run_synthesis(x: int, y: int, target_freq_mhz: float) -> dict:
    """Run Yosys synthesis + OpenROAD P&R."""
    results_dir = os.path.join(AUDIT_DIR, "experiments", f"x{x}", f"y{y}")
    os.makedirs(results_dir, exist_ok=True)
    
    # Config files
    config_mk = os.path.join(FLOW_DIR, "config.mk")
    constraint_sdc = os.path.join(FLOW_DIR, "constraint.sdc")
    
    if not Path(config_mk).exists():
        return {"error": f"Missing {config_mk}"}
    
    # Update constraint with target frequency
    period_ns = 1000.0 / target_freq_mhz
    with open(constraint_sdc, "w") as f:
        f.write(f"create_clock [get_ports clk] -period {period_ns:.3f} -name clk\n")
        f.write("set_input_delay 0.5 -clock clk [all_inputs]\n")
        f.write("set_output_delay 0.5 -clock clk [all_outputs]\n")
    
    # Run OpenROAD flow
    # This assumes ORFS is set up; adjust path as needed
    orfs_path = os.environ.get("ORFS_PATH", "/home/kit/OpenROAD-flow-scripts")
    make_cmd = [
        "make", "-C", orfs_path, 
        f"DESIGN_CONFIG={config_mk}",
        "RESULTS_DIR=" + results_dir,
        "route"
    ]
    
    print(f"[SYNTH] Running: {' '.join(make_cmd)}")
    
    try:
        result = subprocess.run(
            make_cmd,
            capture_output=True,
            text=True,
            timeout=3600,  # 1 hour timeout
            cwd=orfs_path
        )
        
        return {
            "success": result.returncode == 0,
            "stdout": result.stdout[-5000:] if result.stdout else "",
            "stderr": result.stderr[-2000:] if result.stderr else "",
            "results_dir": results_dir,
            "timing_report": os.path.join(results_dir, "base", "timing.rpt"),
            "area_report": os.path.join(results_dir, "base", "area.rpt"),
            "drc_report": os.path.join(results_dir, "base", "drc.rpt"),
        }
    except subprocess.TimeoutExpired:
        return {"error": "Synthesis timed out after 1 hour"}
    except Exception as e:
        return {"error": str(e)}


def run_golden_test(rtl_files: list) -> dict:
    """
    Verify RTL against nano-kpu reference model.
    TODO: implement actual comparison
    """
    # Placeholder - should run simulation and compare outputs
    return {
        "golden_pass": None,
        "note": "Golden test not yet implemented"
    }


def generate_next_goal(score: dict, current_goal: str) -> str:
    """Generate goal for next Y iteration based on analysis."""
    path_type = score.get("critical_path_type", "unknown")
    suggestions = score.get("suggestions", [])
    freq = score.get("freq_mhz", 0)
    target = score.get("target_freq_mhz", 100)
    
    if score.get("pass"):
        # Met target, push higher
        new_target = int(freq * 1.2)
        return f"Achieved {freq:.1f} MHz. Push to {new_target} MHz. Optimize {path_type} path."
    
    # Failed, suggest fix
    suggestion = suggestions[0] if suggestions else "manual analysis"
    return f"Failed at {freq:.1f} MHz (target {target}). Critical path: {path_type}. Try: {suggestion}"


def run_iteration(x: int, y: int, dry_run: bool = False) -> dict:
    """Run a single X.Y iteration."""
    print(f"\n{'='*60}")
    print(f"[ITERATION] X{x}Y{y}")
    print(f"{'='*60}")
    
    # Load goal
    goal = load_goal(x, y)
    print(f"[GOAL] {goal}")
    
    # Get RTL
    rtl_files = get_rtl_files(x, y)
    print(f"[RTL] {len(rtl_files)} files")
    
    # Determine target frequency
    if x == 1 and y == 1:
        target_freq = HARNESS_CONFIG["baseline_freq_mhz"]
    else:
        # Progressive targets
        last = get_last_trial()
        if last and last.get("freq_mhz"):
            # Try 10% higher than last achieved
            target_freq = last["freq_mhz"] * 1.1
        else:
            target_freq = HARNESS_CONFIG["baseline_freq_mhz"]
    
    print(f"[TARGET] {target_freq:.1f} MHz")
    
    if dry_run:
        print("[DRY RUN] Would run synthesis here")
        return {"dry_run": True, "x": x, "y": y, "target_freq_mhz": target_freq}
    
    # Run synthesis
    synth_result = run_synthesis(x, y, target_freq)
    
    if "error" in synth_result:
        print(f"[ERROR] {synth_result['error']}")
        trial = {
            "x": x,
            "y": y,
            "goal": goal,
            "timestamp": datetime.now().isoformat(),
            "error": synth_result["error"],
            "pass": False,
        }
        save_trial(trial)
        return trial
    
    # Score results
    score = score_iteration(
        synth_result.get("timing_report", ""),
        synth_result.get("area_report", ""),
        synth_result.get("drc_report", ""),
        target_freq
    )
    
    # Golden test
    golden = run_golden_test(rtl_files)
    
    # Build trial record
    trial = {
        "x": x,
        "y": y,
        "goal": goal,
        "timestamp": datetime.now().isoformat(),
        "rtl_files": rtl_files,
        "target_freq_mhz": target_freq,
        **score,
        **golden,
    }
    
    # Generate next goal suggestion
    if not score.get("pass"):
        next_goal = generate_next_goal(score, goal)
        trial["suggested_next_goal"] = next_goal
        print(f"[SUGGEST] {next_goal}")
    
    # Save
    save_trial(trial)
    
    # Print summary
    print(f"\n[RESULT]")
    print(f"  Pass: {score.get('pass')}")
    print(f"  Freq: {score.get('freq_mhz', 0):.1f} MHz (target {target_freq:.1f})")
    print(f"  WNS: {score.get('wns_ns')} ns")
    print(f"  Area: {score.get('area_um2')} um²")
    print(f"  DRC: {score.get('drc_count')} violations")
    print(f"  Critical path: {score.get('critical_path_type')}")
    print(f"  Suggestions: {score.get('suggestions')}")
    
    return trial


def main():
    parser = argparse.ArgumentParser(description="Harness v2 iteration runner")
    parser.add_argument("--x", type=int, help="X version")
    parser.add_argument("--y", type=int, help="Y iteration")
    parser.add_argument("--auto", action="store_true", help="Auto-increment from last trial")
    parser.add_argument("--dry-run", action="store_true", help="Don't actually run synthesis")
    parser.add_argument("--goal", type=str, help="Override goal text")
    args = parser.parse_args()
    
    trials = load_trials()
    
    if args.auto:
        x, y = get_next_xy(trials)
    elif args.x and args.y:
        x, y = args.x, args.y
    else:
        # Default to X1Y1
        x, y = 1, 1
    
    # Override goal if provided
    if args.goal:
        save_goal(x, y, args.goal)
    
    result = run_iteration(x, y, dry_run=args.dry_run)
    
    print(f"\n[DONE] Trial saved to {TRIALS_FILE}")
    return result


if __name__ == "__main__":
    main()
