# X6-Y4: Synthesis

## Goal
Synthesize all X6 RTL blocks to Nangate45, targeting 500 MHz. Report area, timing, and power estimates.

## Required Reading
1. `/home/kit/kimi-chip/experiments/x6/architecture.json` - area budget (2.21 mm² pre-margin)
2. `/home/kit/kimi-chip/experiments/x6/Y3_SUMMARY.md` - verified RTL status
3. All RTL in `/home/kit/kimi-chip/experiments/x6/rtl/`

## Synthesis Flow

### Tool Setup
- Use Yosys for synthesis
- Target: Nangate45 (use existing liberty files in the kimi-chip repo or OpenROAD-flow-scripts)
- Clock period: 2.0 ns (500 MHz)
- Check `/home/kit/kimi-chip/` for existing synthesis scripts to reference

### Blocks to Synthesize
1. `mac_array_16x16.v` - expect ~0.17 mm² per array (reference X4-Y5)
2. `state_update.v` - expect ~0.17 mm²
3. `conv_unit.v` - expect ~0.04 mm²
4. `norm_unit.v` - expect ~0.03 mm²
5. `residual_unit.v` - small
6. `weight_crossbar.v` - expect ~0.035 mm²
7. `activation_crossbar.v` - expect ~0.035 mm²

### SRAM Handling
- Replace behavioral SRAM with Nangate45 SRAM macros (fakeram45_*)
- Or: synthesize without SRAM, note SRAM area separately using architecture.json estimates

## Output Requirements
1. Synthesis scripts: `/home/kit/kimi-chip/experiments/x6/flow/synth_*.tcl` or `*.ys`
2. Area report: `/home/kit/kimi-chip/experiments/x6/artifacts/area_report.txt`
3. Timing report: `/home/kit/kimi-chip/experiments/x6/artifacts/timing_report.txt`
4. `/home/kit/kimi-chip/experiments/x6/Y4_SUMMARY.md` with:
   - Per-block area vs budget comparison
   - Timing slack (positive = meets 500 MHz, negative = fails)
   - Critical path identification
   - Any RTL changes needed to meet timing

## Success Criteria
- All blocks meet 500 MHz (positive slack)
- Total logic area < 0.7 mm² (excluding SRAM)
- If timing fails, identify fixes for Y5

Do NOT run P&R, commit, or push.
