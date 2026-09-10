"""
Parse OpenROAD timing reports and classify critical paths.
"""

import re
import json
from pathlib import Path
from typing import Optional
from config import PATH_TYPES, FIX_SUGGESTIONS, MODEL_CONFIG


def parse_timing_report(report_path: str) -> dict:
    """Parse OpenROAD timing report for key metrics."""
    result = {
        "wns_ns": None,         # worst negative slack
        "tns_ns": None,         # total negative slack
        "freq_mhz": None,       # achieved frequency
        "critical_path": [],    # list of cells in critical path
        "critical_path_raw": "",
        "slack_met": False,
    }
    
    if not Path(report_path).exists():
        return result
    
    with open(report_path) as f:
        content = f.read()
    
    # Parse WNS
    wns_match = re.search(r"wns\s+([-\d.]+)", content, re.IGNORECASE)
    if wns_match:
        result["wns_ns"] = float(wns_match.group(1))
        result["slack_met"] = result["wns_ns"] >= 0
    
    # Parse TNS
    tns_match = re.search(r"tns\s+([-\d.]+)", content, re.IGNORECASE)
    if tns_match:
        result["tns_ns"] = float(tns_match.group(1))
    
    # Parse clock period to get frequency
    period_match = re.search(r"clock\s+period\s*[=:]\s*([\d.]+)", content, re.IGNORECASE)
    if period_match:
        period_ns = float(period_match.group(1))
        if period_ns > 0:
            result["freq_mhz"] = 1000.0 / period_ns
    
    # Extract critical path (cells between startpoint and endpoint)
    path_section = re.search(
        r"Startpoint:.*?Endpoint:.*?slack\s+\(.*?\)",
        content,
        re.DOTALL | re.IGNORECASE
    )
    if path_section:
        result["critical_path_raw"] = path_section.group(0)
        # Extract cell names
        cells = re.findall(r"(\w+)/(\w+)\s+\((\w+)\)", path_section.group(0))
        result["critical_path"] = [
            {"instance": c[0], "pin": c[1], "cell_type": c[2]} for c in cells
        ]
    
    return result


def parse_area_report(report_path: str) -> dict:
    """Parse OpenROAD area report."""
    result = {
        "area_um2": None,
        "utilization": None,
        "cell_count": None,
    }
    
    if not Path(report_path).exists():
        return result
    
    with open(report_path) as f:
        content = f.read()
    
    area_match = re.search(r"Design area\s+([\d.]+)", content, re.IGNORECASE)
    if area_match:
        result["area_um2"] = float(area_match.group(1))
    
    util_match = re.search(r"utilization\s+([\d.]+)", content, re.IGNORECASE)
    if util_match:
        result["utilization"] = float(util_match.group(1))
    
    cell_match = re.search(r"Instances\s*[=:]\s*(\d+)", content, re.IGNORECASE)
    if cell_match:
        result["cell_count"] = int(cell_match.group(1))
    
    return result


def parse_drc_report(report_path: str) -> dict:
    """Parse DRC violation report."""
    result = {
        "drc_count": 0,
        "drc_types": {},
    }
    
    if not Path(report_path).exists():
        return result
    
    with open(report_path) as f:
        content = f.read()
    
    # Count total violations
    violations = re.findall(r"violation", content, re.IGNORECASE)
    result["drc_count"] = len(violations)
    
    # Categorize by type
    types = re.findall(r"(\w+)\s+violation", content, re.IGNORECASE)
    for t in types:
        result["drc_types"][t] = result["drc_types"].get(t, 0) + 1
    
    return result


def classify_critical_path(timing_result: dict) -> str:
    """Classify critical path type based on cells."""
    path_str = timing_result.get("critical_path_raw", "").lower()
    cells = timing_result.get("critical_path", [])
    
    # Check each path type
    for path_type, keywords in PATH_TYPES.items():
        for kw in keywords:
            if kw.lower() in path_str:
                return path_type
            for cell in cells:
                if kw.lower() in cell.get("instance", "").lower():
                    return path_type
                if kw.lower() in cell.get("cell_type", "").lower():
                    return path_type
    
    return "unknown"


def get_suggestions(path_type: str) -> list:
    """Get fix suggestions for a path type."""
    return FIX_SUGGESTIONS.get(path_type, ["manual analysis needed"])


def estimate_memory_bandwidth(freq_mhz: float, max_seq: int = None) -> dict:
    """
    Estimate memory bandwidth requirements and tokens/sec.
    
    MLA: O(T) reads per token (K[0:T] and V[0:T])
    KDA: Fixed-size read-modify-write
    """
    if max_seq is None:
        max_seq = MODEL_CONFIG["max_seq"]
    
    mla_dk = MODEL_CONFIG["mla_dk"]
    mla_dr = MODEL_CONFIG["mla_dr"]
    mla_dv = MODEL_CONFIG["mla_dv"]
    n_heads = MODEL_CONFIG["n_heads"]
    kda_dim = MODEL_CONFIG["kda_dim"]
    kda_heads = MODEL_CONFIG["kda_heads"]
    
    # Per-token memory accesses at max sequence length
    # MLA: read K[T, H, dk+dr] and V[T, H, dv] 
    mla_k_bytes = max_seq * n_heads * (mla_dk + mla_dr) * 2  # 2 bytes per element
    mla_v_bytes = max_seq * n_heads * mla_dv * 2
    mla_total = mla_k_bytes + mla_v_bytes
    
    # KDA: read and write state [H, dim, dim]
    kda_state_bytes = kda_heads * kda_dim * kda_dim * 2 * 2  # read + write
    
    # Cycles estimate (naive: 1 element per cycle)
    mla_cycles = max_seq * n_heads * ((mla_dk + mla_dr) + mla_dv)
    kda_cycles = kda_heads * kda_dim * kda_dim * 2  # read + write
    
    # Tokens per second (very rough)
    cycles_per_token = mla_cycles + kda_cycles  # simplified
    if freq_mhz and freq_mhz > 0:
        tokens_per_sec = (freq_mhz * 1e6) / cycles_per_token
    else:
        tokens_per_sec = 0
    
    return {
        "mla_bytes_per_token": mla_total,
        "kda_bytes_per_token": kda_state_bytes,
        "total_bytes_per_token": mla_total + kda_state_bytes,
        "est_cycles_per_token": cycles_per_token,
        "est_tokens_per_sec": tokens_per_sec,
        "max_seq": max_seq,
    }


def score_iteration(
    timing_report: str,
    area_report: str,
    drc_report: str,
    target_freq_mhz: float,
) -> dict:
    """
    Score a synthesis/P&R iteration.
    Returns combined metrics and pass/fail status.
    """
    timing = parse_timing_report(timing_report)
    area = parse_area_report(area_report)
    drc = parse_drc_report(drc_report)
    
    path_type = classify_critical_path(timing)
    suggestions = get_suggestions(path_type)
    
    freq_achieved = timing.get("freq_mhz", 0) or 0
    bandwidth = estimate_memory_bandwidth(freq_achieved)
    
    # Pass criteria
    freq_pass = freq_achieved >= target_freq_mhz
    drc_pass = drc["drc_count"] == 0
    overall_pass = freq_pass and drc_pass
    
    return {
        "pass": overall_pass,
        "freq_pass": freq_pass,
        "drc_pass": drc_pass,
        "freq_mhz": freq_achieved,
        "target_freq_mhz": target_freq_mhz,
        "wns_ns": timing.get("wns_ns"),
        "tns_ns": timing.get("tns_ns"),
        "area_um2": area.get("area_um2"),
        "utilization": area.get("utilization"),
        "cell_count": area.get("cell_count"),
        "drc_count": drc["drc_count"],
        "drc_types": drc["drc_types"],
        "critical_path_type": path_type,
        "suggestions": suggestions,
        "bandwidth": bandwidth,
    }


if __name__ == "__main__":
    # Test with dummy data
    print("Scoring module loaded.")
    print(f"Path types: {list(PATH_TYPES.keys())}")
    print(f"Fix suggestions available for: {list(FIX_SUGGESTIONS.keys())}")
    bw = estimate_memory_bandwidth(100)
    print(f"Bandwidth estimate at 100 MHz: {bw}")
