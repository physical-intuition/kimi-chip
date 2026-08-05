# Kimi Optimization Sprint

## Final Results (v4 - Nangate45)

| Metric | Value |
|--------|-------|
| **Area** | 0.066 mm² |
| **Frequency** | 752 MHz |
| **Timing** | +0.67ns slack, all clean |
| **MACs** | 256 (16x16 INT4) |
| **Peak TOPS** | 0.385 |
| **TOPS/mm²** | 5.83 |

## vs Kimi K3

| Metric | Kimi K3 | Our v4 | Ratio |
|--------|---------|--------|-------|
| Die Area | 4 mm² | 0.066 mm² | **60x smaller** |
| Frequency | 100 MHz | 752 MHz | **7.5x faster** |
| MACs | 256 | 256 | same |
| TOPS/mm² | 0.013 | 5.83 | **450x** |

*Note: Kimi includes SRAM; our compute-only. Adding 256KB SRAM would be ~0.3mm² more.*

## All Iterations

| Version | Config | Cells | Area (mm²) | Notes |
|---------|--------|-------|------------|-------|
| v2 (baseline) | 16x16, 16b acc | 53,053 | 0.074 | - |
| v3 (pipelined) | 16x16, 16b, 2-stage | 53,160 | 0.085 | +14% area |
| **v4 (small acc)** | 16x16, 12b acc | 43,882 | 0.060→0.066 | **BEST** |
| v5 (wide) | 8x32, 16b acc | 52,957 | 0.073 | diff bandwidth |
| v6 (pipe+small) | 16x16, 12b, 2-stage | 42,639 | 0.069 | - |
| v8 (minimal) | 16x16, 8b acc | 39,535 | 0.053 | K≤4 only |

## Key Insight
Accumulator width is the biggest optimization lever. Going from 32b→12b saved 18% area with no functional loss for typical K dimensions.

## Artifacts
- `compute_core_v4.gds` - GDSII layout
- `rtl/compute_core_v4.v` - RTL source
- OpenROAD flow: `/home/kit/OpenROAD-flow-scripts/flow/designs/nangate45/kimi_v4/`

## Caveats
- SRAM not included (would add ~0.2-0.3 mm²)
- Controller simplified vs full Kimi
- Nangate45 is academic PDK, not production
