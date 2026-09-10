"""
Harness configuration for kimi-chip audit synthesis runs.
Model config matches MoonshotAI/nano-kpu reference.
"""

# === Nano-KPU Model Config ===
MODEL_CONFIG = {
    "d_model": 64,
    "n_layers": 2,
    "layer_pattern": "LF",  # layer 0 = KDA, layer 1 = MLA
    "kda_heads": 2,
    "kda_dim": 32,
    "conv_kernel": 4,
    "n_heads": 2,
    "mla_dk": 32,
    "mla_dr": 16,
    "mla_dv": 32,
    "mla_dc": 128,
    "max_seq": 64,
    "vocab": 512,
}

# === Memory Requirements (bytes) ===
MEMORY_REQS = {
    "kda_state_per_layer": 8 * 1024,      # 8 KiB
    "conv_hist_per_kda_layer": 2304,       # 2.25 KiB
    "mla_k_cache_per_layer": 24 * 1024,    # 24 KiB
    "mla_v_cache_per_layer": 16 * 1024,    # 16 KiB
    "total_state_cache": 50 * 1024,        # ~50 KiB
}

# === Harness Iteration Config ===
HARNESS_CONFIG = {
    "platform": "nangate45",
    "baseline_freq_mhz": 100,       # X1Y1 target
    "plateau_threshold": 0.05,      # 5% - trigger X bump if 3+ Y within this
    "plateau_count": 3,
    "max_y_per_x": 10,
    "max_x": 10,
}

# === Critical Path Classification ===
PATH_TYPES = {
    "sram_read": ["SRAM", "mem_rd", "cache_rd", "kv_rd"],
    "sram_write": ["mem_wr", "cache_wr", "state_wr"],
    "accumulator": ["acc", "adder", "sum"],
    "multiplier": ["mul", "mult", "product"],
    "mux": ["mux", "select", "fanout"],
    "routing": ["wire", "buf", "CLKBUF"],
}

# === Structured Fix Suggestions ===
FIX_SUGGESTIONS = {
    "sram_read": [
        "add read pipeline stage",
        "bank SRAM (2-way or 4-way)",
        "prefetch next address",
        "reduce read width, fold over cycles",
    ],
    "sram_write": [
        "write buffer / posted write",
        "bank SRAM",
    ],
    "accumulator": [
        "hierarchical fold (12b → 24b)",
        "reduce accumulator width",
        "pipeline accumulation",
        "tree reduction",
    ],
    "multiplier": [
        "pipeline multiplier",
        "reduce operand width",
        "booth encoding",
    ],
    "mux": [
        "encode differently (one-hot → binary)",
        "pipeline mux output",
        "reduce fanout with buffer tree",
    ],
    "routing": [
        "relax placement density",
        "add buffer stages",
        "adjust floorplan",
    ],
}

# === Paths ===
import os
HARNESS_DIR = os.path.dirname(os.path.abspath(__file__))
AUDIT_DIR = os.path.dirname(HARNESS_DIR)
RTL_DIR = os.path.join(AUDIT_DIR, "rtl")
FLOW_DIR = os.path.join(HARNESS_DIR, "flow")
GOALS_DIR = os.path.join(HARNESS_DIR, "goals")
TRIALS_FILE = os.path.join(HARNESS_DIR, "trials.jsonl")
