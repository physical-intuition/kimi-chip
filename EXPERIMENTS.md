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


## X4: Golden-model functional correctness (harness 4)
Harness: RTL vs Python reference, cycle-by-cycle (golden.py) and exact per-tensor (operator models), strict inference gate that must fail until full inference exists. Normative spec: MoonshotAI/nano-kpu reference/model.py (vendored at third_party/nano-kpu, commit e1855de, SHA-256 pinned from X4Y4). Weights are synthetic throughout.
Directory note: dataflow/x4y4, x4y4_reports, x4y5*, x5y* are pre-scheme physical-flow runs (old numbering), not harness-4/5 iterations; they are not renumbered.

| variant | change | verification | result | dir | commit |
|---|---|---|---|---|---|
| X4Y1 | full-top arithmetic diagnostic + strict inference gate | golden.py cycle model | diagnostic match, strict fails (correctly) | x4y1_golden | 077c37d |
| X4Y2 | MLA cache bounds, backpressure until restart, projection storage overflow | + bounds/protocol tbs | pass, strict fails | x4y2_bounds | f9d340d |
| X4Y3 | KDA operators (proj, conv+SiLU, L2, gates, delta rule, gated norm, o-proj) | RTL == kda_model exact, 6 tok / 2 seq | exact, strict fails | x4y3_kda | 3e8f7c2 |
| X4Y4 | MLA operators (latent wc + knorm RMSNorm, q/kr from h, kc/v decompression, KV cache in 9x512x64 SRAM, NoPE scores, LUT softmax, p@V, o-proj); reference int4 dequant (z, Q3.12 s, group 128/64) with official seeded weights; KDA fixes (f/z rank 32, gated-norm eps 1e-5) | RTL == mla_model / kda_model exact on 6 tok, 66 tok (64-entry cache, refused 65th, restart), group 64; mla_model vs model.py `_mla` | exact; MLA out cos vs model.py >= 0.99965 (64-entry cache); strict fails (MLA input staged, no norm/MoE/residual/head) | x4y4_mla | X4Y4_COMMIT |

### X4 learnings
- X4Y4: checking the X4Y3 KDA float model against model.py itself (not a re-derivation) exposed two structural deviations (rank 8 vs kda_dim 32, eps 1e-6 vs 1e-5; up to 155% of max|out| on early tokens) that an RTL==own-model exact match cannot see. From X4Y4 on, every operator is also compared to RefModel directly.
- X4Y4: MLA error vs reference is dominated by INT8 coding of lat/ctx at the MAC input, not by softmax (LUT < 1.5e-4) or the latent norm (cos > 0.99999).
- X4Y4: KDA fixed point is weak on the first token of a sequence (cos 0.983 vs model.py); revisit numerics before logits are judged.
- X4Y4: Icarus 13 rejects use-before-declaration; X4Y4 RTL is order-clean, frozen X4Y2/X4Y3 need Icarus <= 12.
- Next: X4Y5 norm + MoE + residual wiring (feeds KDA output into MLA, replaces the staged h), then X5 harness work.
