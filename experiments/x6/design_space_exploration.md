# X6-Y1 Design Space Exploration

## Common assumptions

All configurations implement one 128-dimensional KDA head, use INT4 projection weights, INT8 activations, INT24 persistent state, and run at 500 MHz for the conservative throughput comparison. Each 16x16 array supplies 256 MACs/cycle, so a 128x128 projection always consumes 16,384 / 256 = 64 array cycles.

Every configuration uses the factored two-pass recurrence:

```
A = diag(alpha) S
u = k^T A
d = beta(v-u)
S_new = A + k d^T
```

The query is fused into the final state pass. State-update cycles with L lanes are approximately:

```
pass 1 = 16,384 / L
vector delta = ceil(128 / L) * 2 registered operations
pass 2 = 16,384 / L
state cycles = 32,768 / L + 2*ceil(128/L)
```

For L=32, 128, and 256 this gives 1,032, 258, and 130 cycles respectively.

Area uses 0.17 mm2 per 16x16 MAC and 0.5 mm2 per 64 KiB SRAM. All totals include a 25% physical uncertainty margin.

## Summary

| Config | MAC arrays | Weight banks | State lanes | State epoch / II | 500 MHz throughput | 750 MHz throughput | Area with 25% margin | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| A conservative | 1 | 4 | 32 | 1,032 cycles | 484,496 tok/s | 726,744 tok/s | 2.450 mm2 | Meets targets, inefficient latency |
| B balanced | 2 | 6 | 128 | 258 cycles | 1,937,984 tok/s | 2,906,977 tok/s | 2.7625 mm2 | Chosen |
| C memory-rich | 2 | 8 | 128 | 258 cycles | 1,937,984 tok/s | 2,906,977 tok/s | 2.925 mm2 | No throughput gain |
| D aggressive | 4 | 8 | 256 | 130 cycles | 3,846,154 tok/s | 5,769,231 tok/s | 3.675 mm2 | Too little area margin |

All four exceed the 10,000-token/s requirement. The comparison therefore optimizes implementation risk and utilization rather than chasing throughput that the product does not require.

## Configuration A: conservative

Configuration A has one 16x16 MAC array, four weight banks, a 32-lane state datapath, an 8-stage control decomposition, and sequential projection scheduling.

Projection work is:

```
K + V + Q + O = 4 * 64 = 256 array cycles/token
```

With 32 state lanes, each matrix pass needs:

```
16,384 / 32 = 512 cycles
```

The recurrence epoch is 1,032 cycles: 512 cycles for scale/reduce, eight cycles for two 128-element vector operations at 32 lanes, and 512 cycles for update/query. State recurrence dominates the single 256-cycle projection engine, so the steady II is 1,032 cycles.

```
500 MHz throughput = 500,000,000 / 1,032 = 484,496 tokens/s
750 MHz throughput = 750,000,000 / 1,032 = 726,744 tokens/s
```

Pre-margin area is 1.96 mm2. It consists of 1.50 mm2 SRAM, 0.17 mm2 MAC, 0.06 mm2 state datapath, and 0.23 mm2 for convolution, norm, crossbar, control, and interfaces.

```
Area with margin = 1.96 * 1.25 = 2.450 mm2
```

A is safe but unattractive. It saves only 2.7625 - 2.450 = 0.3125 mm2 versus B while increasing II by 1,032 / 258 = 4.000x. The long state epoch also increases live-buffer lifetime and verification complexity.

## Configuration B: balanced

Configuration B has two 16x16 arrays, six 256-bit weight banks, a 128-lane state datapath, and the 11-stage logical control decomposition from the baseline spec. The actual first-token latency is 482 cycles; logical stage count must not be confused with cycle count.

The state epoch is:

```
Pass 1 = 16,384 / 128 = 128 cycles
Delta = 2 cycles
Pass 2 plus query = 16,384 / 128 = 128 cycles
II = 128 + 2 + 128 = 258 cycles
```

```
500 MHz throughput = 500,000,000 / 258 = 1,937,984 tokens/s
750 MHz throughput = 750,000,000 / 258 = 2,906,977 tokens/s
```

The two arrays execute 256 array-cycles of projection work within 2 * 258 = 516 available array-cycles, giving 256 / 516 = 49.612% aggregate array utilization. Assigned projection windows are 100% occupied. The KDA datapath works for 256 / 258 = 99.225% of the epoch and is the correct bottleneck.

Pre-margin area is 2.21 mm2:

```
Area with margin = 2.21 * 1.25 = 2.7625 mm2
Headroom = 4.0 - 2.7625 = 1.2375 mm2
```

The six-bank fabric provides 6 * 256 = 1,536 bits/cycle, while average weight demand is 33,280 bytes / 258 = 128.992 bytes/cycle = 1,031.94 bits/cycle. Utilization is 1,031.94 / 1,536 = 67.183%.

B is selected because it saturates the recurrent engine, retains 30.94% of the 4 mm2 budget as post-estimate headroom, and has a conflict-free schedule.

## Configuration C: memory-rich

C keeps B's two MAC arrays and 128 state lanes but expands from six to eight weight banks. Compute cycles are unchanged:

```
II = 258 cycles
Throughput at 500 MHz = 1,937,984 tokens/s
```

With eight 256-bit banks:

```
Aggregate width = 8 * 256 = 2,048 bits/cycle = 256 bytes/cycle
Weight utilization = 128.992 / 256 = 50.387%
```

The extra banks do not reduce II because the six-bank design already supplies weights faster than the average consumption rate and local array buffers cover bursts. Wider arbitration and bank periphery raise pre-margin area from 2.21 to 2.34 mm2:

```
Area with margin = 2.34 * 1.25 = 2.925 mm2
```

C pays 0.1625 mm2 after margin for no throughput gain. It is useful only if Y2 finds that macro aspect ratios prevent the six-bank refill schedule.

## Configuration D: aggressive

D has four 16x16 arrays, eight weight banks, a 256-lane state datapath processing two rows per cycle, and a deeper 16-stage logical pipeline.

State cycles are:

```
Pass 1 = 16,384 / 256 = 64 cycles
Delta = 2 registered arithmetic cycles
Pass 2 plus query = 16,384 / 256 = 64 cycles
II = 64 + 2 + 64 = 130 cycles
```

```
500 MHz throughput = 500,000,000 / 130 = 3,846,154 tokens/s
750 MHz throughput = 750,000,000 / 130 = 5,769,231 tokens/s
```

Four projections use 256 array-cycles. Four arrays over 130 cycles provide 520 array-cycles, yielding 256 / 520 = 49.231% aggregate array utilization. The arrays improve schedule flexibility but the doubled state datapath, not the fourth MAC alone, produces the 2x throughput gain.

Pre-margin area is 2.94 mm2:

```
Area with margin = 2.94 * 1.25 = 3.675 mm2
Headroom = 4.0 - 3.675 = 0.325 mm2
```

Only 8.125% of the total area budget remains. That is too little for uncertainty in 3,072-bit SRAM-row packing, CTS, power grid, and high-fanout state buses. D should be reconsidered only after B completes macro-aware P&R with at least 0.6 mm2 measured spare area.

## Sensitivity to the original memory capacities

The original concept allocates 512 KiB weight SRAM and 128 KiB state SRAM. Under the required SRAM estimate:

```
Weight SRAM area = 512 / 64 * 0.5 = 4.0 mm2
State SRAM area = 128 / 64 * 0.5 = 1.0 mm2
Memory-only total = 5.0 mm2
```

No compute configuration can meet a 4 mm2 chip limit with those capacities. This is a hard arithmetic contradiction. Y1 resolves it by scoping the core to one head and reducing weight capacity to 64 KiB. If 512 KiB is a non-negotiable product requirement, the area target must increase above 6 mm2 after compute and routing margin, or a denser SRAM compiler/technology node must be specified.

## Final choice

B wins. A gives up nearly 4x throughput for a small area reduction. C spends area on bandwidth that B does not need. D is fast but leaves only 0.325 mm2 of modeled headroom and creates the riskiest physical structure. B is quantitatively balanced and should become the frozen input to X6-Y2.
