# X9 Y1 result: defined numerical helpers pass, complete datapath remains underspecified

X9 closes the standalone INT24-to-INT8 requantization contract and makes the four projection matrix element addresses precise. It still does not define enough arithmetic, storage, or cycle behavior to implement a bit-exact no-shortcut KDA datapath. `x9_datapath.v`, `x9_top.v`, and a full-chip ABC claim are therefore intentionally absent rather than fabricated.

## Implemented and verified

- Copied the X8 six-bank weight SRAM, ping-pong state SRAM, SRAM simulation macro, and 644-phase-cycle controller unchanged.
- Added `requant_24_to_8.v`, implementing signed arithmetic shift by eight and saturation to [-128, 127].
- Added `weight_addr_gen.v`, implementing the normative row-major packed-word formula and all four matrix bases.
- Added `mac_scheduler.v`, implementing the stated row ownership split only. It explicitly does not pretend to solve the missing reorder-buffer schedule.
- Exhaustively checked all 16,384 K matrix element addresses, all matrix end addresses, requantization boundaries, and rows 63/64 routing.
- Rechecked the copied controller's structural 644-cycle count.
- Synthesized only the three defined helper blocks with Yosys/ABC and Nangate45 at a 2.0 ns target. Pre-layout estimates were 219.88 ps / 21.014 um2 for requantization, 674.40 ps / 82.726 um2 for the address generator, and 22.62 ps / 2.394 um2 for row routing. These are helper-only numbers, not chip timing.

## Blocker 1: gate signedness and nonlinear functions contradict each other

The precision table declares both alpha and beta as unsigned INT8 in [0,255]. The conv section says alpha uses sigmoid and beta uses tanh. A tanh result must represent negative values, so beta cannot obey the stated unsigned contract. The spec also gives no PWL breakpoints, output Q format, bias layout, bias precision, or rounding/saturation rule. The X6 implementation used alpha approximately Q7 unsigned and beta signed Q7, but importing that behavior would be an unstated X9 assumption.

## Blocker 2: the state recurrence has no fixed-point contract

A complete implementation needs exact rules for each of these operations:

```
A[i,j]     = alpha[j] * S[i,j]
u[j]       = sum_i k[i] * A[i,j]
d[j]       = beta[j] * (v[j] - u[j])
S_new[i,j] = A[i,j] + k[i] * d[j]
y[j]       = sum_i q[i] * S_new[i,j]
```

The spec does not say where binary points lie, which shifts follow each multiply, whether reductions saturate per term or only at the end, how subtraction overflows, or whether alpha/beta are per row or per column. INT24 storage width alone does not determine any of these values. The prior X6 state block used signed Q7 multipliers and `>>> 7` after each multiply, but X9 does not authorize that rule and its unsigned beta table conflicts with it.

## Blocker 3: conv history address ranges do not follow the stated striping formula

The kernel counts are consistent: 512 INT4 values are eight 256-bit words. Under the X9 six-bank formula, eight alpha words at base 172 occupy local addresses 172-173, and eight beta words at base 174 occupy 174-175.

History is 384 INT8 values, or 3,072 bits, or twelve 256-bit words. The same striping formula at base 176 occupies only local addresses 176-177. The spec instead assigns 176-183 without defining padding, per-timestep bank placement, or a different history mapping. It also never identifies which vector is shifted into history for the current token. A truthful `conv_addr_gen.v` cannot choose among those layouts.

## Blocker 4: row-major projection storage and the two-MAC schedule are not connected

One SRAM read cycle returns six consecutive packed words, or 384 INT4 weights. Because each row is two words, the row-major stream returns three complete adjacent rows per cycle. It emits rows 0-62 to MAC0's half first, crosses rows 63-65 together, and then emits rows 66-127 to MAC1's half. It does not naturally feed both row-split arrays concurrently.

The two arrays nominally consume 512 weights per compute cycle, while SRAM supplies 384. "Prefetch 2 cycles ahead" does not by itself define a sustainable schedule. The 86-cycle phase has enough average time to load 43 cycles and compute later, but X9 does not specify the required 8 KiB projection reorder buffer, its write/read mapping, accumulator reset/drain cycles, activation broadcast, or which of the 86 cycles load versus execute. As a result, asserting both MAC valids for all 86 cycles is structural activity, not real data flow.

## Blocker 5: copied prefetch controls are registered one cycle too late

`x8_controller.v` drives `state_rd_en`, bank, and row from a clocked always block. A synchronous SRAM samples the old values at the same edge. Therefore setting prefetch during the transition out of CONV cycle 9 causes the SRAM to observe that request at the following edge, during STATE_P1 cycle 0. Row zero becomes available for processing in cycle 1, not cycle 0.

Even ignoring that registered-control edge, the phase wording says STATE_P1 reads row N and processes row N-1 after prefetching row zero. A 128-cycle pass should instead process prefetched row zero while requesting row one, continue through row 127, and reserve the last cycle for drain. The copied controller requests `state_row = phase_cycle`, which re-requests row zero. STATE_P2 has the same unresolved fill/drain indexing issue, plus a claimed two-stage process delay.

## Blocker 6: norm and residual integration inputs are not defined

The schedule allocates 24 cycles to RMSNorm and eight to residual, but X9 gives no RMS epsilon, reciprocal-square-root approximation, norm weight format, binary point, or location of the skip vector. Those choices affect bit-exact output and full-top storage.

## Required X10 contract

A realizable next spec should provide a bit-exact reference function for conv, both state passes, delta, query, norm, and residual; a cycle table listing every buffer read/write and valid; a concrete projection reorder-buffer layout; corrected combinational or one-cycle-advanced SRAM controls; and an unambiguous conv history map. A small Python golden model should be normative before RTL is attempted.
