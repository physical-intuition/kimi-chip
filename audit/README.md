# Audit: kimi-chip vs nano-kpu Reference

This folder contains a **corrected implementation** of the Kimi K3 inference chip
that properly matches MoonshotAI's official reference at:
https://github.com/MoonshotAI/nano-kpu/blob/main/reference/model.py

## Problem Statement

The original kimi-chip (X1-X7) achieved 728 MHz on "full dataflow" but **omitted
critical state management** for both attention mechanisms:

1. **MLA KV Cache**: Reference has `kv_k[li].append(k)` - a GROWING cache that
   scales with sequence length T. kimi-chip had no KV cache SRAM.

2. **KDA State**: Reference has `kda_state[i]` of shape `[kda_heads, kda_dim, kda_dim]`.
   kimi-chip X9 had state SRAM but wrong dimensions (128×3072 vs 2×32×32).

3. **Conv History**: Reference has `conv_hist[i]` of shape `[3, kernel-1, kda_heads*kda_dim]`
   for the causal depthwise conv on Q/K/V. kimi-chip had conv compute but no history buffer.

## This Audit Adds

| Module | File | Purpose |
|--------|------|---------|
| `conv_history` | `rtl/conv_history.v` | Shift register for [3, 3, 64] conv history |
| `mla_kv_cache` | `rtl/mla_kv_cache.v` | Growing KV cache SRAM for MLA layers |
| `kda_state_sram` | `rtl/kda_state_sram.v` | Fixed [2,32,32] state for KDA layers |
| `layer_controller` | `rtl/layer_controller.v` | FSM for LF pattern (KDA→MLA alternation) |
| `audit_top` | `rtl/audit_top.v` | Top-level wiring it all together |

## Nano Config (from reference)

```python
d_model=64, n_layers=2, layer_pattern="LF"
kda_heads=2, kda_dim=32, conv_kernel=4
n_heads=2, mla_dk=32, mla_dr=16, mla_dv=32, mla_dc=128
max_seq=64, vocab=512
```

## Memory Requirements

| Component | Shape | Elements | Bits | Size |
|-----------|-------|----------|------|------|
| KDA State (per layer) | [2, 32, 32] | 2,048 | 65,536 | 8 KiB |
| Conv History (per KDA layer) | [3, 3, 64] | 576 | 18,432 | 2.25 KiB |
| MLA K Cache (per layer) | [64, 2, 48] | 6,144 | 196,608 | 24 KiB |
| MLA V Cache (per layer) | [64, 2, 32] | 4,096 | 131,072 | 16 KiB |

Total for nano (2 layers, one KDA + one MLA):
- KDA layer: 8 KiB + 2.25 KiB = 10.25 KiB
- MLA layer: 24 KiB + 16 KiB = 40 KiB
- **Total: ~50 KiB** state/cache storage

## Running

```bash
# Compile check
cd audit
iverilog -o tb_audit_top.vvp tb/tb_audit_top.v rtl/*.v

# Simulate
vvp tb_audit_top.vvp

# View waveforms
gtkwave tb_audit_top.vcd
```

## TODO

- [ ] Wire MAC arrays to controller phases
- [ ] Add actual embedding ROM
- [ ] Add LM head projection
- [ ] Add weight SRAM integration
- [ ] Synthesis and timing closure
- [ ] Golden test against nano-kpu reference outputs
