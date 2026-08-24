# X8 Y1 result: corrected storage/control, complete numerical integration blocked

X8 fixes X7's macro capacities and O/state dependency. Y1 implemented and tested the realizable storage wrappers and exact 644-cycle controller, but intentionally did not fabricate a complete KDA result path. The remaining spec gaps determine numerical behavior, so the no-shortcut checklist cannot truthfully pass yet.

## What Y1 proves

- `weight_sram_6bank.v` instantiates exactly 12 `fakeram45_128x256` macros as six logical 256x256 banks.
- `state_sram_pingpong.v` instantiates exactly 24 macros as two 128x3072-bit banks.
- The SRAM simulation test programs and reads all six weight banks and both state banks.
- `x8_controller.v` runs exactly 644 busy cycles in the legal order K, V, Q, conv, state P1, delta, state P2, O, norm, residual.
- Both MAC enables are active in every projection phase and O's input-valid cannot assert until state P2 completes.
- State bank roles swap after each token. Row-zero prefetches in the final conv and delta cycles make the 128-cycle state phases compatible with synchronous SRAM latency.
- Yosys/ABC mapped the controller against Nangate45. ABC reported 470.83 ps combinational delay and Yosys reported 489.44 um^2 cell area. This is controller-only pre-layout timing, not full-chip timing.

## Blocker 1: projection/state precision boundaries are undefined

K/V/Q projection outputs are INT24 accumulators, while the state recurrence consumes INT8 k, q, and v scalars. State P2 produces an INT24 reduction vector, while the O projection consumes an activation vector. X8 does not specify requantization scales, rounding, saturation, zero points, or where those registers live.

Taking the low byte, as the old X6 integration test did, is a shortcut and is numerically wrong for signed fixed-point values. Saturating directly to INT8 is only one arbitrary choice. Without this contract, an end-to-end golden model cannot distinguish a correct implementation from a convenient one.

Required X9 addition: define every tensor's signed format and the exact INT24-to-INT8 requantization operation for K, V, Q, and state-P2 y before O.

## Blocker 2: the stated element address formula is not a physical SRAM address

The literal formula `bank=(row*128+col)%6, addr=(row*128+col)/6` produces addresses up to 2730, but each logical bank is only 256 words deep. A physical address also needs a nibble lane because each 256-bit word stores 64 INT4 elements.

Y1 used the packed interpretation:

```
e = row*128 + col
word = floor(e/64)
bank = word % 6
addr = matrix_base + floor(word/6)
lane = e % 64
```

This must be made normative, including whether the matrix is row-major or tile-major. The choice controls the transpose/reorder buffer and MAC scheduler.

## Blocker 3: conv storage and gate inputs are unspecified

The four 128x128 matrices occupy 172 addresses per bank, leaving 84 addresses per bank. That is enough capacity, but X8 does not define the packed addresses for alpha/beta kernels and biases, history layout, or how ten conv cycles generate all 128 gate values. No-shortcut verification needs this map and a programmed nonzero conv test.

## Blocker 4: exact boundary overlap must be contractual

A `fakeram45_128x256` read is synchronous. A 128-row state pass cannot include its own read fill and datapath drain in exactly 128 isolated cycles. Y1 makes 644 cycles possible by prefetching state row zero during the last conv cycle and prefetching intermediate row zero during the second delta cycle. X9 should explicitly permit these cross-phase prefetches and define where the final row drains.

## Stop decision

The corrected SRAM and control architecture is feasible, but full no-shortcut RTL and full-chip ABC timing are not meaningful until the fixed-point and packing contracts above are specified. Y1 stops under the fundamental-blocker condition rather than inventing quantization or claiming controller timing as chip timing.
