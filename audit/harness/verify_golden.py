#!/usr/bin/env python3
"""
Golden test: verify RTL simulation matches nano-kpu reference model.

Usage:
    python verify_golden.py [--rtl-dir PATH] [--num-tokens N]
"""

import argparse
import subprocess
import sys
from pathlib import Path

# nano-kpu reference path (clone if not present)
NANO_KPU_PATH = Path.home() / "nano-kpu"
NANO_KPU_REPO = "https://github.com/MoonshotAI/nano-kpu.git"


def ensure_nano_kpu():
    """Clone nano-kpu reference if not present."""
    if not NANO_KPU_PATH.exists():
        print(f"Cloning nano-kpu to {NANO_KPU_PATH}...")
        subprocess.run(
            ["git", "clone", NANO_KPU_REPO, str(NANO_KPU_PATH)],
            check=True
        )
    return NANO_KPU_PATH


def run_reference_model(input_tokens: list, config: dict = None) -> dict:
    """
    Run nano-kpu reference model on input tokens.
    Returns state traces for comparison.
    """
    ensure_nano_kpu()
    
    # TODO: import nano-kpu model and run forward pass
    # Capture:
    # - KDA state after each token
    # - KV cache after each token
    # - Conv history after each token
    # - Output logits
    
    return {
        "kda_states": [],      # [T, layers, heads, dim, dim]
        "kv_k_cache": [],      # [T, layers, heads, dk+dr]
        "kv_v_cache": [],      # [T, layers, heads, dv]
        "conv_history": [],    # [T, layers, 3, kernel-1, dim]
        "outputs": [],         # [T, vocab]
        "implemented": False,
    }


def run_rtl_simulation(rtl_dir: str, input_tokens: list) -> dict:
    """
    Run RTL simulation with iverilog/verilator.
    Returns state traces for comparison.
    """
    # TODO: compile RTL, run with input tokens, capture VCD/outputs
    
    return {
        "kda_states": [],
        "kv_k_cache": [],
        "kv_v_cache": [],
        "conv_history": [],
        "outputs": [],
        "implemented": False,
    }


def compare_traces(ref: dict, rtl: dict, tolerance: float = 1e-6) -> dict:
    """Compare reference and RTL traces."""
    mismatches = []
    
    for key in ["kda_states", "kv_k_cache", "kv_v_cache", "conv_history", "outputs"]:
        ref_data = ref.get(key, [])
        rtl_data = rtl.get(key, [])
        
        if len(ref_data) != len(rtl_data):
            mismatches.append({
                "key": key,
                "issue": f"length mismatch: ref={len(ref_data)}, rtl={len(rtl_data)}"
            })
            continue
        
        # TODO: element-wise comparison with tolerance
    
    return {
        "pass": len(mismatches) == 0,
        "mismatches": mismatches,
        "note": "Not yet implemented - placeholder"
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rtl-dir", type=str, default="../rtl")
    parser.add_argument("--num-tokens", type=int, default=8)
    args = parser.parse_args()
    
    print("Golden verification (stub)")
    print(f"RTL dir: {args.rtl_dir}")
    print(f"Num tokens: {args.num_tokens}")
    
    # Generate test tokens
    input_tokens = list(range(args.num_tokens))
    
    # Run both
    print("\nRunning reference model...")
    ref = run_reference_model(input_tokens)
    
    print("Running RTL simulation...")
    rtl = run_rtl_simulation(args.rtl_dir, input_tokens)
    
    # Compare
    print("Comparing traces...")
    result = compare_traces(ref, rtl)
    
    if result["pass"]:
        print("\n✓ GOLDEN TEST PASSED")
    else:
        print("\n✗ GOLDEN TEST FAILED")
        for m in result["mismatches"]:
            print(f"  - {m['key']}: {m['issue']}")
    
    return result


if __name__ == "__main__":
    main()
