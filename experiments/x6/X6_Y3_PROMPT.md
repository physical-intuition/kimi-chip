# X6-Y3: Integration and Testbenches

## Goal
Create comprehensive testbenches for all X6 RTL blocks and verify functional correctness.

## Required Reading
1. `/home/kit/kimi-chip/experiments/x6/architecture.json` - cycle budgets and specs
2. `/home/kit/kimi-chip/experiments/x6/Y2_SUMMARY.md` - what was built in Y2
3. All RTL in `/home/kit/kimi-chip/experiments/x6/rtl/`

## Testbenches to Create

### 1. MAC Array Testbench
- File: `/home/kit/kimi-chip/experiments/x6/tb/tb_mac_array.v`
- Test weight loading
- Test GEMV computation (128×128 matrix × 128 vector)
- Verify 64-cycle completion
- Check accumulator overflow handling
- Golden model comparison

### 2. State Update Testbench
- File: `/home/kit/kimi-chip/experiments/x6/tb/tb_state_update.v`
- Test the full KDA recurrence: S_new = (I - β k k^T) diag(α) S + β k v^T
- Verify two-pass operation (128 + 128 + 2 = 258 cycles)
- Check INT24 precision preservation
- Compare against Python golden model values

### 3. Conv Unit Testbench
- File: `/home/kit/kimi-chip/experiments/x6/tb/tb_conv_unit.v`
- Test depthwise convolution (kernel=4, channels=128)
- Verify 10-cycle completion
- Test sigmoid/tanh approximation accuracy
- Check both alpha and beta outputs

### 4. Norm Unit Testbench
- File: `/home/kit/kimi-chip/experiments/x6/tb/tb_norm_unit.v`
- Test RMSNorm computation
- Verify 24-cycle completion
- Check fixed-point accuracy (note Y2 caveat about reciprocal-root)

### 5. Integration Testbench
- File: `/home/kit/kimi-chip/experiments/x6/tb/tb_x6_integration.v`
- Wire up full dataflow: input → projections → gates → state update → norm → output
- Test one complete token through the pipeline
- Verify cycle count matches architecture.json budget

## Test Methodology
- Use `$readmemh` for test vectors
- Create Python script to generate golden values: `/home/kit/kimi-chip/experiments/x6/tb/gen_golden.py`
- Store test vectors in `/home/kit/kimi-chip/experiments/x6/tb/vectors/`
- Use assertions for protocol checks
- Print PASS/FAIL summary

## Output Requirements
1. All testbench files listed above
2. Python golden model script
3. Test vector files
4. `/home/kit/kimi-chip/experiments/x6/Y3_SUMMARY.md` with:
   - Which tests pass/fail
   - Any bugs found in Y2 RTL (fix them!)
   - Cycle count verification results

## Success Criteria
- All individual block tests pass
- Integration test completes one token with correct output
- No RTL bugs remaining

Do NOT run synthesis, commit, or push.
