# X6-Y1 Architecture Rationale

## Decision

Choose configuration B: two 16x16 GEMV arrays, six 256-bit weight banks, a dedicated 128-lane KDA state datapath, 128 KiB of ping-pong state/buffer SRAM, and a 500 MHz signoff target. The design accepts a token every 258 cycles in steady state, giving 500,000,000 / 258 = 1,937,984 tokens/s of single-head compute capacity. Its estimated area is 2.21 mm2 before a 25% physical-design margin and 2.7625 mm2 after margin.

The 11-cycle diagram in `X6_SPEC.md` is conceptual, not a realizable cycle budget. A 128x128 GEMV alone requires 64 cycles on 256 MACs. Y1 replaces that diagram with the quantitative schedule below.

## Scope and precision

The unit of analysis is one KDA head with dimension 128. Weights are INT4, activations are INT8, and persistent state and arithmetic accumulators are INT24.

A 128x128 INT24 state is:

```
128 * 128 * 24 / 8 = 49,152 bytes = 48 KiB
```

Two ping-pong state images require 96 KiB. The remaining 32 KiB of the 128 KiB state allocation holds projected K/V/Q vectors, convolution history, residual data, output buffers, and macro alignment.

Four 128x128 INT4 projection matrices plus two depthwise convolution kernels require:

```
4 * 128 * 128 * 4 / 8 = 32,768 bytes
2 * 128 channels * 4 taps * 4 / 8 = 512 bytes
Total live weights = 33,280 bytes = 32.5 KiB
```

A 64 KiB, six-logical-bank allocation therefore has 30.5 KiB of headroom. Keeping the original 512 KiB weight allocation is not possible under the supplied area model: 512 / 64 * 0.5 = 4.0 mm2 for weight SRAM alone, already at the total-chip limit. The selected capacity is a necessary one-head correction, not an unexplained optimization.

## Algebraic reduction of the KDA recurrence

The specified recurrence is:

```
S_new = (I - beta k k^T) diag(alpha) S + beta k v^T
```

Define:

```
A = diag(alpha) S
u = k^T A
d = beta (v - u)
```

Then:

```
S_new = A - beta k u^T + beta k v^T
      = A + k [beta(v-u)]^T
      = A + k d^T
```

This avoids materializing either 128x128 outer-product matrix. It needs two streaming passes over state. Pass 1 scales rows and reduces `u`. Pass 2 applies the rank-1 update. During pass 2, the design also accumulates `q^T S_new`, so KDA query needs no third state read.

## Cycle budget

### K, V, Q, and O projections

Each projection computes 128 outputs, each with a length-128 dot product:

```
MAC operations = 128 * 128 = 16,384
MACs per 16x16 array = 16 * 16 = 256 MAC/cycle
Cycles = 16,384 / 256 = 64 cycles
```

Therefore K, V, Q, and O each take 64 array cycles. The four projections consume 4 * 64 = 256 array-cycles per token.

### Alpha and beta convolution gates

Assume the KDA depthwise convolution has 128 channels and kernel size 4. A 16-lane gate datapath evaluates 16 channels each cycle. Alpha and beta have separate 16-lane multiplier groups and run together.

```
Channels per gate = 128
Channels per cycle = 16
Dot-product cycles = 128 / 16 = 8
PWL sigmoid/tanh pipeline latency = 2
Parallel alpha+beta latency = 8 + 2 = 10 cycles
```

The two gates perform `2 * 128 * 4 = 1,024` INT8xINT4 products.

### State scale and reduction pass

The state SRAM presents one complete 128-element INT24 row per cycle. Its row width is:

```
128 elements * 24 bits = 3,072 bits = 384 bytes
```

For row `i`, 128 lanes compute `A[i,j] = alpha[i] * S[i,j]` and accumulate `u[j] += k[i] * A[i,j]` for all 128 columns. There are 128 rows:

```
Elements processed = 128 * 128 = 16,384
Parallel lanes = 128
Cycles = 16,384 / 128 = 128
```

This pass reads 48 KiB from one state bank and writes 48 KiB of A into the other bank.

### Delta vector

For 128 elements, 128 scalar lanes compute subtraction and beta scaling. Registering each arithmetic boundary gives:

```
Cycle 1: e[j] = v[j] - u[j]
Cycle 2: d[j] = beta * e[j]
Total = 2 cycles
```

### State update and fused query pass

For each state row, 128 lanes compute:

```
S_new[i,j] = A[i,j] + k[i] * d[j]
query[j] += q[i] * S_new[i,j]
```

The update and query are pipelined within each lane. After pipeline fill, one row is accepted per cycle. The fixed fill/drain registers are included in the two boundary cycles above, so the architectural pass budget remains one cycle per row:

```
Elements = 16,384
Lanes = 128
Cycles = 16,384 / 128 = 128
```

The complete recurrent block takes:

```
128 scale/reduce + 2 delta + 128 update/query = 258 cycles
```

### RMSNorm

A 16-lane unit handles 128 values in eight cycles per vector pass:

```
Square and reduction = 128 / 16 = 8 cycles
Reciprocal-square-root PWL/Newton pipeline = 8 cycles
Scale and quantize = 128 / 16 = 8 cycles
Total = 24 cycles
```

### Residual and writeback

Sixteen lanes add and saturate 128 elements. The output interface accepts the resulting 16 bytes each cycle:

```
128 / 16 = 8 cycles
```

Writeback is fused with this pass, so it adds no separate cycles.

## First-token latency

K and Q begin together. MAC0 computes K during cycles 0-63 and V during 64-127. MAC1 computes Q during 0-63. Conv runs during 0-9. All state-update inputs are ready after cycle 127.

```
Projection frontier = 128 cycles
State update plus fused query = 258 cycles
O projection = 64 cycles
RMSNorm = 24 cycles
Residual/writeback = 8 cycles
First-token latency = 128 + 258 + 64 + 24 + 8 = 482 cycles
At 500 MHz: 482 / 500,000,000 = 0.964 microseconds
```

## Steady-state pipeline schedule

The recurrence prevents two state updates for the same head from overlapping. It does not prevent the next token's K/V/Q projections from running while the current token occupies the state unit. Double-buffered projection vectors decouple the stages.

| Absolute cycles | MAC0 | MAC1 | Conv | KDA state unit | Norm/residual |
|---:|---|---|---|---|---|
| 0-9 | K0 | Q0 | alpha0+beta0 | idle | idle |
| 10-63 | K0 | Q0 | idle | idle | idle |
| 64-127 | V0 | idle | idle | idle | idle |
| 128-191 | K1 | Q1 | token 1 at 128-137 | token 0 pass 1 | idle |
| 192-255 | V1 | idle | idle | token 0 pass 1 | idle |
| 256-257 | idle | idle | idle | token 0 delta | idle |
| 258-385 | idle | idle | idle | token 0 pass 2 plus query | idle |
| 386-449 | K2 | O0 | token 2 at 386-395 | token 1 pass 1 | idle |
| 450-513 | V2 | Q2 | idle | token 1 pass 1 | O0 feeds norm at 450-473, residual at 474-481 |
| 514-515 | idle | idle | idle | token 1 delta | idle |
| 516-643 | idle | idle | idle | token 1 pass 2 plus query | idle |
| 644-707 | K3 | O1 | token 3 at 644-653 | token 2 pass 1 | idle |
| 708-771 | V3 | Q3 | idle | token 2 pass 1 | O1 feeds norm and residual |

After warm-up, a new state epoch starts every 258 cycles. The initiation interval is therefore 258 cycles, while first-token latency is 482 cycles. O projection, normalization, and residual work are hidden under the next recurrent epoch and do not increase the initiation interval.

No MAC conflict occurs. In epochs where the prior token needs O projection, MAC0 handles K then V; MAC1 handles O then Q. Each occupies exactly 64 cycles.

## Throughput and compute utilization

At 500 MHz:

```
Throughput = 500,000,000 / 258 = 1,937,984 tokens/s
Target margin = 1,937,984 / 10,000 = 193.8x
```

At 750 MHz:

```
Throughput = 750,000,000 / 258 = 2,906,977 tokens/s
```

The two MAC arrays provide 512 MAC slots/cycle. A token uses 65,536 projection MACs:

```
Average projection MACs/cycle = 65,536 / 258 = 254.016
Projection-array utilization = 254.016 / 512 = 49.612%
```

That figure is below 50% because two arrays are required for dependency-safe overlap, not because memory starves them. During an assigned projection, an array consumes all 256 slots. The recurrent datapath accepts rows during 256 of each 258 cycles:

```
KDA lane utilization = 256 / 258 = 99.225%
```

For the two main arithmetic fabrics, count occupied lane slots:

```
Projection occupied slots = 65,536
KDA occupied slots = 2 passes * 16,384 = 32,768
Available slots = 258 * (512 projection lanes + 128 KDA lanes) = 165,120
Combined utilization = (65,536 + 32,768) / 165,120 = 59.535%
```

Thus the system-level arithmetic utilization exceeds 50%, and the limiting resource is the deliberately saturated state updater.

## Bandwidth

### Per-token traffic

| Traffic | Derivation | Bytes |
|---|---:|---:|
| Input vector read | 128 INT8 | 128 |
| Four projection weight reads | 4 * 128 * 128 * 0.5 | 32,768 |
| Four projection vector writes | 4 * 128 INT8 | 512 |
| Conv weight reads | 2 * 128 * 4 * 0.5 | 512 |
| Conv history reads | 128 * 4 INT8 | 512 |
| Conv gate writes | 2 * 128 INT8 | 256 |
| State pass 1 read+write | 2 * 128 * 128 * 3 | 98,304 |
| State pass 2 read+write | 2 * 128 * 128 * 3 | 98,304 |
| Norm read+write | 2 * 128 INT8 | 256 |
| Residual skip read | 128 INT8 | 128 |
| Final output write | 128 INT8 | 128 |
| Total | sum | 231,808 bytes = 226.375 KiB |

At the required 10,000 tokens/s:

```
231,808 bytes/token * 10,000 token/s = 2,318,080,000 bytes/s = 2.31808 GB/s
```

A 256-bit activation/interface bus at 500 MHz provides:

```
256 / 8 * 500,000,000 = 16,000,000,000 bytes/s = 16 GB/s
Target utilization = 2.31808 / 16 = 14.488%
```

State traffic never uses that shared bus. It stays between two local ping-pong SRAM banks. Each state pass needs one 3,072-bit read and one 3,072-bit write each cycle. Separate source and destination banks provide those operations concurrently, for 6,144 bits/cycle aggregate local state movement.

The six weight banks are each 256 bits wide:

```
Aggregate weight width = 6 * 256 = 1,536 bits = 192 bytes/cycle
Aggregate bandwidth at 500 MHz = 192 * 500,000,000 = 96 GB/s
Weight+conv bytes/token = 32,768 + 512 = 33,280 bytes
Average bytes/cycle at II 258 = 33,280 / 258 = 128.992 bytes/cycle
Weight-bank utilization = 128.992 / 192 = 67.183%
```

Two 2,048-bit local weight buffers feed active MAC arrays at full rate. The banks refill those buffers across the epoch. This is why a narrow 256-bit shared weight bus was rejected: it would provide only 16 GB/s and cap the core below its compute ceiling even though it would still exceed the 10,000-token target.

## Area budget

The supplied evidence is 0.17 mm2 for one 16x16 MAC array and 0.5 mm2 per 64 KiB SRAM. Smaller arithmetic blocks are scaled from the MAC result, then rounded upward for control, LUTs, and wiring.

| Block | Derivation | Area mm2 |
|---|---:|---:|
| Weight SRAM | 64 KiB / 64 KiB * 0.5 | 0.50 |
| State/buffer SRAM | 128 KiB / 64 KiB * 0.5 | 1.00 |
| Two MAC arrays | 2 * 0.17 | 0.34 |
| 128-lane state datapath | 128/256 * 0.17 raw arithmetic, doubled for two arithmetic boundaries and registers | 0.17 |
| Conv unit | 32/256 * 0.17 + LUT/control rounding | 0.04 |
| Norm and residual | 16-lane square/scale/add plus rsqrt | 0.03 |
| Crossbars and wide local buses | supplied 0.02-0.05 crossbar range plus wide-bus premium | 0.07 |
| Control FSM | supplied estimate | 0.01 |
| Interfaces/output buffer | conservative allowance | 0.05 |
| Pre-margin total | sum | 2.21 |
| Physical uncertainty margin | 2.21 * 25% | 0.5525 |
| Total with margin | 2.21 * 1.25 | 2.7625 |

Area headroom is:

```
4.0 - 2.7625 = 1.2375 mm2
```

The area is an architecture estimate, not a replacement for Y5 macro-aware floorplanning. In particular, the 3,072-bit state rows may incur fragmentation when built from narrow macros. The 25% margin is retained specifically for that risk, clock tree, routing channels, tie/fill cells, and power grid.

## Hazards and mitigations

The state recurrence is a true read-after-write dependency across tokens. The design does not attempt illegal overlap; the 258-cycle state epoch defines the initiation interval.

K, V, Q, alpha, and beta must all be complete before pass 1. Double-buffered projection vectors allow the next token's projections to proceed while the state unit handles the current token.

O projection competes with Q for MAC1. The schedule assigns O to the first 64 cycles and Q to the second 64 cycles of the next 128-cycle projection window. MAC0 simultaneously computes K then V.

State pass 1 produces A and u, while pass 2 consumes A and d. Ping-pong state banks avoid same-bank read/write conflicts. Bank roles swap each token.

The 1,536-bit weight-bank fabric is narrower than the instantaneous two-array demand. Per-array local buffers absorb that mismatch; average refill demand is 1,031.94 bits/cycle, below the 1,536-bit supply.

## Conclusion

Configuration B is the smallest option that keeps the state updater continuously occupied while leaving a clean schedule for K/V/Q/O. Configuration A saves only 0.3125 mm2 after margin but is four times slower. Configuration C adds banks without improving the 258-cycle recurrence limit. Configuration D doubles throughput but consumes 3.675 mm2 estimated area and leaves too little physical margin. B is the right Y2 starting point.
