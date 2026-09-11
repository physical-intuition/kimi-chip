#!/usr/bin/env python3
"""
X2 Harness: Timing Analysis -> Architectural Proposals

Key capability vs X1: X2 reads timing reports and derives what to fix.

X1 could only: try random variations, check if they compile
X2 can: read timing reports, identify bottleneck, propose targeted fix
"""

import re
import sys
from pathlib import Path

def parse_reg_to_reg_path(report_path):
    """Extract the worst reg-to-reg setup path from 6_finish.rpt"""
    text = Path(report_path).read_text()
    
    # Find the reg-to-reg section specifically
    match = re.search(
        r"finish report_checks -path_delay max reg to reg\s+-+\s+"
        r"Startpoint:\s+(\S+).*?"
        r"Endpoint:\s+(\S+).*?"
        r"(\d+\.\d+)\s+slack \(MET\)",
        text, re.DOTALL
    )
    
    if not match:
        return None
    
    startpoint = match.group(1)
    endpoint = match.group(2)
    slack = float(match.group(3))
    
    # Extract the path section between startpoint and slack
    path_section = match.group(0)
    
    # Find arrival time
    arrival_match = re.search(r"(\d+\.\d+)\s+data arrival time", path_section)
    arrival = float(arrival_match.group(1)) if arrival_match else 0
    
    # Parse individual stages
    stages = []
    for line in path_section.split("\n"):
        # Look for delay entries like "   0.14    0.46 ^ _8801_/CO (HA_X1)"
        stage_match = re.search(r"\s+(\d+\.\d+)\s+(\d+\.\d+)\s+[v^]\s+(\S+)\s+\((\w+)\)", line)
        if stage_match:
            stages.append({
                "delay": float(stage_match.group(1)),
                "time": float(stage_match.group(2)),
                "name": stage_match.group(3),
                "cell": stage_match.group(4)
            })
    
    # Classify stages
    buffer_stages = [s for s in stages if "BUF" in s["cell"] or s["name"].startswith("place")]
    logic_cells = ["HA_X1", "FA_X1", "AND2_X1", "AND2_X2", "OR2_X1", 
                   "NAND2_X1", "NAND2_X2", "NOR2_X1", "NOR2_X4",
                   "NOR3_X1", "AOI21_X1", "OAI21_X1", "OAI22_X1",
                   "INV_X1", "XOR2_X1"]
    logic_stages = [s for s in stages if s["cell"] in logic_cells]
    
    buffer_delay = sum(s["delay"] for s in buffer_stages)
    logic_delay = sum(s["delay"] for s in logic_stages)
    
    return {
        "startpoint": startpoint,
        "endpoint": endpoint,
        "arrival_ns": arrival,
        "slack_ns": slack,
        "stages": stages,
        "buffer_stages": len(buffer_stages),
        "logic_stages": len(logic_stages),
        "buffer_delay_ns": buffer_delay,
        "logic_delay_ns": logic_delay,
        "bottleneck": "fanout" if buffer_delay > logic_delay else "logic_depth"
    }

def classify_path_type(startpoint, endpoint):
    """Classify the path type for targeted fix proposal"""
    start_lower = startpoint.lower()
    end_lower = endpoint.lower()
    
    if ("ctrl" in start_lower or "phase" in start_lower or "current" in start_lower):
        if "history" in end_lower or "conv" in end_lower:
            return "controller_to_conv_history"
        elif "state" in end_lower or "kda" in end_lower:
            return "controller_to_kda_state"
        elif "mla" in end_lower or "cache" in end_lower:
            return "controller_to_mla_cache"
    
    if "history" in start_lower and "history" in end_lower:
        return "conv_history_internal"
    if "state" in start_lower and "state" in end_lower:
        return "kda_state_internal"
    
    return "other"

def propose_fix(analysis):
    """Propose architectural fix based on timing analysis"""
    proposals = []
    path_type = classify_path_type(analysis["startpoint"], analysis["endpoint"])
    
    if path_type == "controller_to_conv_history":
        # This is the common case: controller generates addr/enable that fans out to history buffer
        
        if analysis["bottleneck"] == "fanout":
            proposals.append({
                "change": "Register conv_history write address before fanout",
                "rationale": f"Buffer stages account for {analysis['buffer_delay_ns']:.2f} ns ({analysis['buffer_stages']} stages). Adding a pipeline register before the high-fanout signal reduces timing pressure.",
                "expected_improvement_ns": analysis["buffer_delay_ns"] * 0.5,
                "code_change": "Add reg [LOG2_DEPTH-1:0] wr_addr_q; and use it for memory writes",
            })
        
        if analysis["logic_stages"] >= 4:
            proposals.append({
                "change": "Pipeline the address calculation",
                "rationale": f"Logic path has {analysis['logic_stages']} stages ({analysis['logic_delay_ns']:.2f} ns). Half of this can be hidden by registering the intermediate result.",
                "expected_improvement_ns": analysis["logic_delay_ns"] * 0.4,
                "code_change": "Split addr calc into 2 cycles: cycle 1 computes base, cycle 2 adds offset",
            })
        
        proposals.append({
            "change": "Bank conv_history into 2 or 4 banks",
            "rationale": "Reduces per-bank fanout, shorter wires, faster muxes.",
            "expected_improvement_ns": 0.15,
            "code_change": "addr[LOG2_DEPTH-1:LOG2_DEPTH-2] selects bank, rest is bank-local addr",
        })
    
    elif path_type == "controller_to_kda_state":
        proposals.append({
            "change": "Use SRAM macro for kda_state",
            "rationale": "Behavioral SRAM expands to registers. SRAM macros have fixed, predictable timing.",
            "expected_improvement_ns": 0.20,
            "code_change": "Instantiate fakeram45_256x32 or similar",
        })
    
    else:
        # Generic proposals
        if analysis["logic_stages"] >= 5:
            proposals.append({
                "change": "Add pipeline register in combinational path",
                "rationale": f"{analysis['logic_stages']} logic stages is too deep for high frequency.",
                "expected_improvement_ns": analysis["logic_delay_ns"] * 0.35,
            })
    
    return proposals

def main(report_path):
    analysis = parse_reg_to_reg_path(report_path)
    if not analysis:
        print("ERROR: Could not parse reg-to-reg critical path")
        return
    
    path_type = classify_path_type(analysis["startpoint"], analysis["endpoint"])
    
    print("=" * 60)
    print("X2 HARNESS: TIMING ANALYSIS")
    print("=" * 60)
    print()
    print("Critical reg-to-reg path:")
    print(f"  {analysis['startpoint']}")
    print(f"    -> {analysis['endpoint']}")
    print()
    print(f"Path type: {path_type}")
    print(f"Arrival time: {analysis['arrival_ns']:.2f} ns")
    print(f"Slack: {analysis['slack_ns']:.2f} ns")
    current_period = 10.0 - analysis['slack_ns']
    print(f"Achievable fmax: {1000/current_period:.0f} MHz (at 10ns target)")
    print()
    print("Path breakdown:")
    print(f"  Buffer stages: {analysis['buffer_stages']} ({analysis['buffer_delay_ns']:.2f} ns)")
    print(f"  Logic stages:  {analysis['logic_stages']} ({analysis['logic_delay_ns']:.2f} ns)")
    print(f"  Bottleneck: {analysis['bottleneck'].upper()}")
    print()
    
    proposals = propose_fix(analysis)
    proposals_sorted = sorted(proposals, key=lambda x: x["expected_improvement_ns"], reverse=True)
    
    print("=" * 60)
    print("PROPOSED FIXES (ranked by expected impact)")
    print("=" * 60)
    for i, p in enumerate(proposals_sorted, 1):
        print()
        print(f"{i}. {p['change']}")
        print(f"   Rationale: {p['rationale']}")
        print(f"   Expected improvement: ~{p['expected_improvement_ns']:.2f} ns")
        if "code_change" in p:
            print(f"   Code change: {p['code_change']}")
    
    print()
    print("=" * 60)
    print("DERIVED TARGET FOR NEXT Y ITERATION")
    print("=" * 60)
    if proposals_sorted:
        best = proposals_sorted[0]
        new_period = current_period - best["expected_improvement_ns"]
        print(f"Current: period {current_period:.2f} ns -> {1000/current_period:.0f} MHz")
        print(f"Target:  period {new_period:.2f} ns -> {1000/new_period:.0f} MHz")
        print(f"Fix to implement: {best['change']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: x2_analyze.py <path_to_6_finish.rpt>")
        sys.exit(1)
    main(sys.argv[1])
