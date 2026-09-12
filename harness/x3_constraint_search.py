#!/usr/bin/env python3
"""
X3 Harness: Constraint-Driven Optimization with SDC Search

Key insight from X2Y3 -> X2Y4 -> X2Y5:
- Same RTL achieved 1080 MHz @ 10ns target, 1792 MHz @ 1.0ns target, 1877 MHz @ 0.6ns target
- Constraint tightening alone gave +74% improvement!
- P&R tools "sandbag" with relaxed constraints - they stop when slack is met

X3 Strategy:
1. Start with aggressive constraint (e.g., 0.5ns)
2. If timing met with slack > 0.05ns, tighten further
3. If timing violations, back off
4. Track history to find the achievable ceiling
5. Only propose RTL changes when constraint ceiling is hit
"""

import re
import sys
import json
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Optional, Tuple

@dataclass
class TimingResult:
    target_period_ns: float
    achieved_period_ns: float
    fmax_mhz: float
    slack_ns: float
    violations: int
    power_mw: float

def parse_finish_report(report_path: str) -> Optional[dict]:
    """Extract key metrics from 6_finish.rpt"""
    text = Path(report_path).read_text()
    
    period_match = re.search(r'period_min = (\d+\.?\d*)', text)
    fmax_match = re.search(r'fmax = (\d+\.?\d*)', text)
    slack_match = re.search(r'worst slack max (-?\d+\.?\d*)', text)
    
    setup_viol = re.search(r'setup violation count (\d+)', text)
    hold_viol = re.search(r'hold violation count (\d+)', text)
    
    power_match = re.search(r'Total\s+[\d.e+-]+\s+[\d.e+-]+\s+[\d.e+-]+\s+([\d.e+-]+)', text)
    
    if not (period_match and fmax_match):
        return None
    
    achieved_period = float(period_match.group(1))
    fmax = float(fmax_match.group(1))
    slack = float(slack_match.group(1)) if slack_match else 0
    violations = 0
    if setup_viol:
        violations += int(setup_viol.group(1))
    if hold_viol:
        violations += int(hold_viol.group(1))
    power = float(power_match.group(1)) * 1000 if power_match else 0
    
    return {
        "achieved_period_ns": achieved_period,
        "fmax_mhz": fmax,
        "slack_ns": slack,
        "violations": violations,
        "power_mw": power
    }

def parse_sdc_period(sdc_path: str) -> float:
    """Extract clock period from SDC file"""
    text = Path(sdc_path).read_text()
    match = re.search(r'create_clock.*-period\s+(\d+\.?\d*)', text)
    return float(match.group(1)) if match else 10.0

def calculate_next_constraint(results_history: List[Tuple[float, dict]]) -> Tuple[float, str]:
    """
    Calculate next constraint target based on history.
    Returns (next_target_ns, rationale)
    """
    if not results_history:
        return 0.5, "Starting with aggressive 0.5ns target"
    
    last_target, last_result = results_history[-1]
    
    if last_result["violations"] > 0:
        # Back off by 15%
        next_target = last_target * 1.15
        return next_target, f"Backing off from {last_target:.3f}ns due to timing violations"
    
    slack = last_result["slack_ns"]
    achieved = last_result["achieved_period_ns"]
    
    if slack > 0.2:
        # Lots of slack - go to achieved + 5% margin
        next_target = achieved * 1.05
        return next_target, f"Large slack ({slack:.3f}ns), targeting achieved period + 5%"
    
    if slack > 0.1:
        # Moderate slack - tighten by 8%
        next_target = last_target * 0.92
        return next_target, f"Moderate slack ({slack:.3f}ns), tightening by 8%"
    
    if slack > 0.03:
        # Tight slack - small step
        next_target = last_target * 0.97
        return next_target, f"Tight slack ({slack:.3f}ns), small 3% tightening"
    
    # Very tight slack - near optimal
    return last_target, f"At optimal - slack is {slack:.3f}ns, cannot tighten further"

def generate_sdc(period_ns: float, io_margin_ratio: float = 0.05) -> str:
    """Generate SDC file content"""
    io_delay = period_ns * io_margin_ratio
    return f"""# X3 auto-generated constraint
# Target: {period_ns:.3f} ns ({1000/period_ns:.1f} MHz)
create_clock [get_ports clk] -period {period_ns:.3f} -name core_clock
set_input_delay {io_delay:.3f} -clock core_clock [all_inputs]
set_output_delay {io_delay:.3f} -clock core_clock [all_outputs]
"""

def analyze_ceiling(results_history: List[Tuple[float, dict]]) -> dict:
    """Check if we've hit the constraint ceiling"""
    if len(results_history) < 2:
        return {"at_ceiling": False, "reason": "Need more data"}
    
    recent = results_history[-3:] if len(results_history) >= 3 else results_history
    fmax_values = [r["fmax_mhz"] for _, r in recent]
    fmax_range = max(fmax_values) - min(fmax_values)
    fmax_avg = sum(fmax_values) / len(fmax_values)
    
    # Check if fmax plateaued (< 2% variation)
    if fmax_range / fmax_avg < 0.02:
        return {
            "at_ceiling": True,
            "ceiling_mhz": fmax_avg,
            "reason": f"fmax plateaued at ~{fmax_avg:.0f} MHz"
        }
    
    # Check if last run had violations
    last_target, last_result = results_history[-1]
    if last_result["violations"] > 0 and len(results_history) >= 2:
        prev_target, prev_result = results_history[-2]
        return {
            "at_ceiling": True,
            "ceiling_mhz": prev_result["fmax_mhz"],
            "reason": f"Violations at {last_target:.3f}ns, ceiling is {prev_result['fmax_mhz']:.0f} MHz"
        }
    
    return {"at_ceiling": False}

def main(report_path: str, sdc_path: str = None, history_file: str = None):
    result = parse_finish_report(report_path)
    if not result:
        print("ERROR: Could not parse timing report")
        return
    
    # Get current target from SDC
    current_target = parse_sdc_period(sdc_path) if sdc_path else 10.0
    result["target_period_ns"] = current_target
    
    # Load/update history
    results_history = []
    if history_file and Path(history_file).exists():
        with open(history_file) as f:
            for line in f:
                entry = json.loads(line)
                results_history.append((entry["target_ns"], entry["result"]))
    
    results_history.append((current_target, result))
    
    # Save updated history
    if history_file:
        with open(history_file, 'a') as f:
            f.write(json.dumps({"target_ns": current_target, "result": result}) + "\n")
    
    print("=" * 70)
    print("X3 HARNESS: CONSTRAINT-DRIVEN OPTIMIZATION")
    print("=" * 70)
    print()
    print(f"Current run @ {current_target:.3f}ns target:")
    print(f"  Achieved:   {result['achieved_period_ns']:.3f} ns")
    print(f"  fmax:       {result['fmax_mhz']:.2f} MHz")
    print(f"  Slack:      {result['slack_ns']:.3f} ns")
    print(f"  Violations: {result['violations']}")
    print(f"  Power:      {result['power_mw']:.2f} mW")
    print()
    
    if len(results_history) > 1:
        print("Optimization history:")
        print("-" * 50)
        for target, r in results_history:
            status = "✓" if r["violations"] == 0 else "✗"
            print(f"  {status} {target:.3f}ns -> {r['fmax_mhz']:.0f} MHz (slack {r['slack_ns']:.3f}ns)")
        print()
    
    ceiling = analyze_ceiling(results_history)
    
    if ceiling["at_ceiling"]:
        print("=" * 70)
        print("CONSTRAINT CEILING REACHED")
        print("=" * 70)
        print(f"Ceiling: ~{ceiling['ceiling_mhz']:.0f} MHz")
        print(f"Reason: {ceiling['reason']}")
        print()
        print("To break through, RTL changes needed:")
        print("  1. Pipeline critical path (add register stage)")
        print("  2. Reduce fanout on high-drive signals")
        print("  3. Use SRAM macros instead of register arrays")
        print("  4. Restructure for shorter combinational chains")
    else:
        next_target, rationale = calculate_next_constraint(results_history)
        
        print("=" * 70)
        print("NEXT ITERATION")
        print("=" * 70)
        print(f"Rationale: {rationale}")
        print(f"Next target: {next_target:.3f} ns ({1000/next_target:.0f} MHz)")
        print()
        print("SDC for next run:")
        print("-" * 50)
        print(generate_sdc(next_target))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: x3_constraint_search.py <6_finish.rpt> [constraint.sdc] [history.jsonl]")
        print()
        print("Example:")
        print("  x3_constraint_search.py audit/x2y5_reports/6_finish.rpt audit/rtl/x2y5/flow/constraint.sdc x3_history.jsonl")
        sys.exit(1)
    
    report = sys.argv[1]
    sdc = sys.argv[2] if len(sys.argv) > 2 else None
    history = sys.argv[3] if len(sys.argv) > 3 else None
    main(report, sdc, history)
