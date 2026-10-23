# kimi-chip-fresh dataflow experiment log

repo: github.com/physical-intuition/kimi-chip
flow: openroad/orfs:latest, nangate45, top = dataflow_top
dims (toy): D_MODEL=32, KDA 2x16, MLA dk16 dr8 dv16 dc32, MAX_SEQ=16, CONV_KERNEL=4, N_LAYERS=2
dims (real/nano-kpu): D_MODEL=64, KDA 2x32, MLA dc=128, MAX_SEQ=64

## X1: FSM skeleton (constraint sweep)
| variant | change | period (ns) | fmax (GHz) | setup ws (ns) | viol | area (um2) | power (mW) | commit |
|---|---|---|---|---|---|---|---|---|
| X1Y1 | FSM skeleton, all phases cycle-counting | 1.0 | 2.294 | - | 0 | ~591 | ~1.0 | 4ee46f1 |
| X1Y2 | constraint tighten | 0.8 | 2.289 | 0.363 | 0 | 591.1 | 1.08 | 618b87a |
| X1Y3 | constraint tighten | 0.6 | 2.317 | 0.168 | 0 | 591.9 | 1.42 | 2a0e823 |
| X1Y4 | constraint tighten | 0.5 | 2.295 | 0.064 | 0 | 592.6 | 1.71 | 9ede9e6 |
| X1Y5 | constraint tighten | 0.48 | 2.347 | 0.054 | 0 | 594.2 | 1.80 | 8a6d8e4 |

## X2: Add real compute (MAC + SRAM)
| variant | change | period (ns) | fmax (GHz) | setup ws (ns) | viol | area (um2) | power (mW) | commit |
|---|---|---|---|---|---|---|---|---|
| X2Y1 | MAC wired into KDA Q/K/V GEMV | 0.6 | 1.687 | 0.007 | 0 | 2234.9 | 3.06 | 9c45739 |
| X2Y2 | MAC into MLA attention (Q.K scores) | 0.6 | 0.876* | -0.542 | 64 | 88121 | 236.3 | 782889c |
| X2Y3 | KV cache -> fakeram45_512x64 SRAM | 0.6 | 0.899* | -0.512 | 272 | 106792 | 258.5 | 090f6f7 |
| X2Y4 | 2-stage pipelined MAC | 0.6 | 1.542* | -0.049 | 108 | 106473 | 264.6 | d52b302 |
| X2Y5 | + set_false_path rst_n | 0.6 | 1.643* | -0.0085 | 2 | 104496 | 254.8 | 1706a52 |

* violates setup timing

## learnings
- X1: FSM-only meets any constraint, sweep uninformative
- X2Y1: adding real GEMV found wall immediately (2.3 -> 1.687 GHz)
- X2Y7: MLA attention costs dearly (1.69 -> 0.876 GHz), KV cache area explodes 2.5k -> 88k um2
- X2Y10: SRAM alone does not fix it, MAC accumulator path exposed
- X2Y11: 2-stage MAC pipeline massive jump (0.899 -> 1.542 GHz)
- X2Y13/Y14: operand staging + reset false path -> 1.643 GHz champion
- X2Y15: true wall ~1.64 GHz at toy dims, argmax compare fanout is binding path

## known gaps vs nano-kpu
- dims 4x small (toy) vs real
- no INT4 group-128 dequant
- no functional/bit-exact verification vs golden model
- harness is still run OpenROAD, read timing without functional validation

## X3: Real dims + functional validation harness (pending)
- X3Y1: D_MODEL=64, dc=128, seq=64, running...
---

## ⚠️ CORRECTNESS STATUS UPDATE (Oct 23, 2026)

**X1Y1 through X3Y5: TIMING VALID, FUNCTIONALLY INVALID**

These iterations measured physical timing on incomplete datapath skeletons. The actual compute (KDA delta rule, MLA softmax/value/output, RMSNorm, MoE routing, residual mixing) was stub or missing. Timing results are real for the hardware that exists, but that hardware does not run full inference.

X4Y1 golden model harness exposed these gaps. X4Y2 fixed some bounds issues but full inference still fails.

**Valid functional work starts at X4Y3 with actual operator implementations.**

---

