# Kimi K3 Chip Specification

## Target to Beat
- Official Kimi K3: 8721 tok/s @ 100 MHz, 4mm²
- Our target: >10,000 tok/s with smaller area

## Architecture (from arxiv.org/abs/2510.26692)
KDA (Kimi Delta Attention) core recurrence:
```
S_t = (I - β_t k_t k_t^T) · diag(α_t) · S_{t-1} + β_t k_t v_t^T
```

### Key Properties
- Fixed 128×128 state per head (no KV cache growth with context)
- INT4 weights, INT8 activations typical
- 3:1 GEMV:matmul ratio mirrors 3:1 KDA:MLA layer ratio

### Compute Requirements
- 16×16 MAC array (256 INT4 MACs)
- SRAM: ~96KB (32KB weights + 32KB activations + 32KB output)

## Success Metrics
- Frequency: >100 MHz (ideally 500+ MHz)
- Area: <4mm² (ideally <1mm²)
- DRC: 0 violations
- Functional: pass testbench
- Sustained throughput, not just peak MAC rate

## PDK
- nangate45 (academic 45nm)
- OpenROAD flow for synthesis + P&R
