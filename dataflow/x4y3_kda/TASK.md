# X4Y3: Implement KDA (Kimi Delta Attention) operators

## Base
Copy from X4Y2 (dataflow/x4y2_bounds/dataflow_top.v). Keep all existing fixes:
- MLA projection 64->32 storage
- attention scanning valid cache only
- backpressure on full cache
- all 6 inherited regression tests pass

## KDA Spec (from nano-kpu docs)

Dimensions: H = kda_heads = 2, dh = kda_dim = 32, P = H*dh = 64

### 1. Projections from normed input x
- q = x @ Wq  (P=64 outputs)
- k = x @ Wk  (P=64)
- v = x @ Wv  (P=64)
- beta_in = x @ Wb  (H=2)
- f = (x @ Wf1) @ Wf2  (P=64, no activation between)
- z = (x @ Wg1) @ Wg2  (P=64)

### 2. Causal depthwise conv (kernel 4) on q, k, v
- Keep previous 3 pre-conv values per stream
- Apply SiLU after conv

### 3. Per head: L2-normalize q and k (eps = 1e-6)

### 4. Gates
- beta = sigmoid(beta_in) per head
- alpha = exp(-5 * sigmoid(A_h * (f + dt_bias)))
  - A_h = exp(A_log) as unsigned Q8.8 per head
  - dt_bias per channel
  - alpha in (e^-5, 1), shape [H=2, dh=32]

### 5. Delta rule on state S (per head [32, 32])
S = diag(alpha_h) * S           # per-key-channel decay
u = v - k*S                     # prediction error
S = S + outer(beta*k, u)
out = (q*S) / sqrt(dh)

### 6. Gated norm per head
- RMSNorm(out, onorm) * sigmoid(z_h)
- onorm weight shared across heads
- gate is plain sigmoid (NOT SiLU)
- concat -> output projection

## Implementation Notes
- INT4 weights (group-128 dequant can be stubbed for now)
- INT8 activations typical
- State S is 2 heads * 32*32 = 2048 values total
- Conv history is 3 taps * 3 streams * 64 channels = 576 values
- Keep the existing MAC array interface - reuse for projections

## Success Criteria
1. All X4Y2 tests still pass
2. KDA projections produce correct dimensions
3. Conv state properly maintained across tokens
4. Delta rule state update matches golden model
5. Golden model updated to track KDA state
6. New tests for KDA-specific behaviors

## NOT in scope (X4Y4+)
- MLA softmax/value/output
- RMSNorm full implementation
- MoE routing
- Residual mixing
