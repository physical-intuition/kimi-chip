# Gap Analysis: kimi-chip vs nano-kpu Reference

## Summary

The blog post at luoluo.ai/blog/kimi-k3 achieved 728 MHz on "full dataflow" but omitted
critical state management for both MLA (KV cache) and KDA (recurrent state). This audit
rebuilds the design to match MoonshotAI's official reference implementation.

## Reference: nano-kpu/reference/model.py

### Model Config (nano)
```
d_model=64, n_layers=2, layer_pattern="LF"  # Layer 0: KDA, Layer 1: MLA
kda_heads=2, kda_dim=32, conv_kernel=4
n_heads=2, mla_dk=32, mla_dr=16, mla_dv=32, mla_dc=128
max_seq=64, vocab=512
```

### State Requirements

#### 1. MLA KV Cache (MISSING in kimi-chip)
```python
# From model.py reset():
self.kv_k[i], self.kv_v[i] = [], []

# From _mla():
self.kv_k[li].append(k.astype(F32))  # k shape: [n_heads, mla_dk+mla_dr] = [2, 48]
self.kv_v[li].append(v.astype(F32))  # v shape: [n_heads, mla_dv] = [2, 32]
K = np.stack(self.kv_k[li])          # [T, H, 48] - GROWS with sequence
V = np.stack(self.kv_v[li])          # [T, H, 32] - GROWS with sequence
```

**Hardware requirement:** 
- K cache: max_seq × n_heads × (mla_dk + mla_dr) = 64 × 2 × 48 = 6144 elements
- V cache: max_seq × n_heads × mla_dv = 64 × 2 × 32 = 4096 elements
- Total per MLA layer: 10240 elements × 32-bit = 40 KiB

#### 2. KDA State (PARTIALLY in kimi-chip, wrong dimensions)
```python
# From model.py reset():
self.kda_state[i] = np.zeros((c.kda_heads, c.kda_dim, c.kda_dim), dtype=F32)
# Shape: [2, 32, 32] = 2048 elements per layer

# From _kda():
S = alpha[hd][:, None] * self.kda_state[li][hd]  # [32, 32] decay
u = vh - kh @ S                                   # delta
S = S + np.outer(kh * beta[hd], u)               # rank-1 update
self.kda_state[li][hd] = S                        # store back
```

**Hardware requirement:**
- State SRAM: kda_heads × kda_dim × kda_dim = 2 × 32 × 32 = 2048 elements × 32-bit = 8 KiB
- Read-modify-write: read S, compute α·S + β·k·uᵀ, write S back
- Per head, per token: one matrix read, one matrix write

#### 3. Conv History (MISSING in kimi-chip)
```python
# From model.py reset():
self.conv_hist[i] = np.zeros((3, c.conv_kernel - 1, c.kda_heads * c.kda_dim), dtype=F32)
# Shape: [3, 3, 64] = 576 elements per KDA layer (for q, k, v streams)

# From _conv():
hist = self.conv_hist[li][stream]                 # [3, 64]
win = np.concatenate([hist, x[None, :]], axis=0)  # [4, 64]
y = silu((win.T * w).sum(axis=-1))                # depthwise conv
self.conv_hist[li][stream] = np.concatenate([hist[1:], x[None, :]], axis=0)  # shift
```

**Hardware requirement:**
- 3 streams × (kernel-1) × (kda_heads × kda_dim) = 3 × 3 × 64 = 576 registers
- Shift register behavior: shift in new, shift out oldest each cycle

## What kimi-chip X7/X9 Has

| Component | Status | Issue |
|-----------|--------|-------|
| MAC Array | ✓ Done | Works, 1047 MHz |
| Weight SRAM | ✓ Done | 6-bank striped |
| State SRAM | ⚠ Wrong | 128×3072 doesn't match [2,32,32] |
| Conv Unit | ⚠ Partial | Compute exists, no history buffer |
| MLA KV Cache | ✗ Missing | No growing cache SRAM |
| Conv History | ✗ Missing | No shift registers |
| Layer Sequencing | ⚠ Wrong | Controller assumes all layers same |

## Audit Plan

### Phase A: State SRAM Fix
- Resize KDA state to [kda_heads, kda_dim, kda_dim] per layer
- Add read-modify-write controller

### Phase B: MLA KV Cache
- Add growing KV cache SRAM per MLA layer
- Add write pointer, softmax attention over variable T

### Phase C: Conv History
- Add 3×(K-1)×D shift register bank per KDA layer
- Wire into conv unit

### Phase D: Layer Controller
- Handle layer_pattern "LF" alternation
- Different dataflow for KDA vs MLA layers
