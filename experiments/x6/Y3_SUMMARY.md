# X6-Y3 Integration and Testbench Summary

## Result

All five Y3 simulations pass with Icarus Verilog 12.0. The vector generator creates 31 deterministic files under `tb/vectors/`, and every functional test compares RTL output against Python-generated expected values.

| Test | Result | Functional coverage | Cycle check |
|---|---:|---|---:|
| `tb_mac_array.v` | PASS | 128x128 signed GEMV, eight output tiles, weight-buffer swaps, INT24 positive saturation | 64 accepted MAC beats |
| `tb_state_update.v` | PASS | `A=diag(alpha)S`, `u=k^T A`, `S_new=A+k d^T`, and fused `q^T S_new`, with signed nontrivial vectors | 128 + 2 + 128 = 258 budget cycles |
| `tb_conv_unit.v` | PASS | 128 depthwise channels, four taps, signed weights and biases, sigmoid/tanh PWL values | 8 channel beats + 2 pipeline stages = 10 budget cycles |
| `tb_norm_unit.v` | PASS | 128-value RMSNorm, integer mean square, rounded Q14 reciprocal RMS, signed INT8 saturation | 8 collect + 8 refine + 8 emit = 24 budget cycles |
| `tb_x6_integration.v` | PASS | Projection, alpha/beta gates, both state passes, fused query, RMSNorm, and residual output for one token | 128 + 258 + 64 + 24 + 8 = 482 first-token budget |

The integration result is bit-exact. A constant-64 identity projection produces alpha and beta of 64, a state update value of 16, fused query values of 1024, normalized values of 1, and final residual values of 4.

## Y2 bugs fixed

The MAC local-weight organization was inconsistent with its datapath. Each buffer was declared as 2048 bits and marked complete after eight 256-bit writes, but the 16x16 datapath only indexed the first 1024 bits. That made half the writes unreachable and prevented a real 128x128 GEMV from selecting a new 16x16 submatrix for each input chunk. Each ping-pong buffer is now one 1024-bit submatrix, completed by four writes. The two buffers still total the architecture's 2048 local bits and permit one submatrix to execute while the other is filled.

The MAC accumulator previously wrapped on INT24 overflow. It now saturates to the signed INT24 range, and the regression drives enough maximum-valued products to verify positive saturation at `0x7fffff`.

The RMSNorm power-of-two reciprocal-root seed could have nearly 2x scale error. Y3 replaces it with a deterministic integer square root and rounded Q14 reciprocal. The varied signed test vector is bit-exact against the Python model. This is a functional reference implementation, not the final timing implementation. Y4 should replace the combinational square-root/divide logic with a characterized LUT and pipelined Newton step before making area or frequency claims.

## Approximation characterization

For the deterministic convolution vectors, RTL is bit-exact against the specified PWL gates. Relative to the software sigmoid and tanh curves under the tested Q7 input interpretation, the generated metrics report maximum absolute normalized errors of 0.062845 for sigmoid and 0.216271 for tanh. The beta PWL approximation is therefore still coarse even though its RTL implementation is correct. A future numerical-quality iteration should characterize or tighten these segments.

## Integration boundary

`rtl/x6_top.v` remains the Y2 ports-only shell. The integration test instantiates and composes the actual MAC, convolution, state-update, norm, and residual blocks in a testbench harness, passing captured outputs into the next stage. It validates the full arithmetic dataflow and architectural budget, but it does not claim that the production SRAM scheduler, external memory handshakes, K/V/Q overlap, or `x6_top` control FSM has been implemented. Those remain controller work rather than arithmetic correctness work.

The 258, 24, and 482 figures are architectural budget cycles. Testbench-only `start` edges, memory-vector loading, buffer refill time, and output observation edges are not counted as datapath budget cycles.

## Reproduction

Run from `experiments/x6`:

```bash
python3 tb/gen_golden.py
mkdir -p /tmp/x6-y3
iverilog -g2012 -Wall -s tb_mac_array -o /tmp/x6-y3/mac_array.vvp tb/tb_mac_array.v rtl/mac_array_16x16.v && vvp /tmp/x6-y3/mac_array.vvp
iverilog -g2012 -Wall -s tb_state_update -o /tmp/x6-y3/state_update.vvp tb/tb_state_update.v rtl/state_update.v && vvp /tmp/x6-y3/state_update.vvp
iverilog -g2012 -Wall -s tb_conv_unit -o /tmp/x6-y3/conv_unit.vvp tb/tb_conv_unit.v rtl/conv_unit.v && vvp /tmp/x6-y3/conv_unit.vvp
iverilog -g2012 -Wall -s tb_norm_unit -o /tmp/x6-y3/norm_unit.vvp tb/tb_norm_unit.v rtl/norm_unit.v && vvp /tmp/x6-y3/norm_unit.vvp
iverilog -g2012 -Wall -s tb_x6_integration -o /tmp/x6-y3/x6_integration.vvp tb/tb_x6_integration.v rtl/mac_array_16x16.v rtl/conv_unit.v rtl/state_update.v rtl/norm_unit.v rtl/residual_unit.v && vvp /tmp/x6-y3/x6_integration.vvp
iverilog -g2012 -Wall -s x6_top -o /tmp/x6-y3/all_rtl.vvp rtl/*.v
```

The final full-RTL compile emits zero warnings. No synthesis, commit, or push was performed.
