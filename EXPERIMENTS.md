# kimi-chip-fresh dataflow experiment log

repo: github.com/physical-intuition/kimi-chip
flow: openroad/orfs:latest, nangate45, top = dataflow_top
dims (current): D_MODEL=32, KDA 2x16, MLA dk16 dr8 dv16 dc32, MAX_SEQ=16, CONV_KERNEL=4, N_LAYERS=2
target dims (nano-kpu): D_MODEL=64, KDA 2x32, MLA dc=128, MAX_SEQ=64

| variant | change | period (ns) | fmax (GHz) | setup ws (ns) | tns | viol | area (um2) | power (mW) | commit |
|---|---|---|---|---|---|---|---|---|---|
| X1Y1 | FSM skeleton, all phases cycle-counting | 1.0 | 2.294 | - | 0 | 0 | ~591 | ~1.0 | 4ee46f1 |
| X1Y2 | constraint tighten | 0.8 | 2.289 | 0.363 | 0 | 0 | 591.1 | 1.08 | 618b87a |
| X1Y3 | constraint tighten | 0.6 | 2.317 | 0.168 | 0 | 0 | 591.9 | 1.42 | 2a0e823 |
| X1Y4 | constraint tighten | 0.5 | 2.295 | 0.064 | 0 | 0 | 592.6 | 1.71 | 9ede9e6 |
| X1Y5 | constraint tighten | 0.48 | 2.347 | 0.054 | 0 | 0 | 594.2 | 1.80 | 8a6d8e4 |
| X2Y1 | MAC wired into KDA Q/K/V GEMV (unpacked weight arrays, muxed reads) | 0.6 | 1.687 | 0.007 | 0 | 0 | 2234.9 | 3.06 | 9c45739 |
| X2Y2 | constraint loosen, wall scales => real path | 0.65 | 1.593 | 0.022 | 0 | 0 | 2194.0 | 2.92 | fcc6c57 |
| X2Y3 | pipeline reg between MAC out and kda_q/k/v writeback | 0.6 | 1.703 | 0.013 | 0 | 0 | 2470.1 | 5.80 | 5e7d017 |
| X2Y4 | weights as shift-register streams (no muxed array reads) | 0.6 | 1.689 | 0.008 | 0 | 0 | 2396.9 | 3.62 | ed08cd3 |
| X2Y5 | argmax precomputed at token load (out of DONE/case fan-in) | 0.6 | 1.697 | 0.011 | 0 | 0 | 2536.8 | 5.77 | bf0f18c |
| X2Y6 | constraint probe (X2Y5 design) | 0.55 | 1.704* | -0.037 | -0.037 | 15 | 2679.7 | 6.80 | TBD |

\* X2Y6 violates: 15 setup viol, ws -0.037ns. true wall of X2 design ~1.70 GHz (~0.587ns)

## learnings
- X1 sweep: FSM-only design meets any constraint -> sweep uninformative
- X2Y1: adding real GEMV compute found wall immediately (2.3 -> 1.687 GHz)
- X2Y2: wall scales with constraint => real logic path, not noise
- X2Y3: writeback pipeline +1% => writeback not the bottleneck
- X2Y4: weight mux not the bottleneck either
- X2Y4 timing report: critical path ends at argmax_reg via FSM case statement; WNS -0.233 at current_layer[2] during repair. next-state decoder fan-in is the wall
- X2Y5: argmax precompute also ~no change (1.697). Y3/Y4/Y5 all 1.69-1.70 => per-fix micro-opt at fixed 0.6ns is noise
- pre-repair WNS -0.243 at kda_q[16]/RN; tool repairs to ~0 => reported fmax is post-repair, single fixes just move the endpoint
- X2Y6 probe: 0.55ns fails (15 viol, ws -0.037) => X2 true wall ~1.70 GHz / 0.587ns. RTL-level fix needed to go faster, not more repair

## X3 series: MLA attention MAC
| X3Y1 | MAC into MLA: real mla_q GEMV + attn score Q.K dot products over KV cache, KV append writes token data | 0.6 | 0.876* | -0.542 | -131 | 64 | 88121 | 236.3 | 782889c |
| X3Y2 | relaxed probe, X3Y1 design | 1.2 | 0.870 CLEAN | 0.051 | 0 | 0 | 87093 | 118.5 | 0fb4d7f |
| X3Y3 | staged q/kv nibbles through regs (break array mux -> MAC) | 0.6 | 0.908* | -0.501 | -104 | 32 | 88094 | 238.3 | TBD |

\* X3Y1 VIOLATES: 64 setup viol, ws -0.542, pre-repair WNS -0.434/-131. real attention compute costs dearly
- X3Y1 learnings: full KV-cache score loop (16 entries x 32 dims, unpacked array reads) is heavy; also 2-layer KV cache storage exploded area 8.8k -> 88k um2, power 5.8 -> 236 mW
- X3Y2: 0.870 GHz CLEAN at 1.2ns => X3 true wall ~0.87 GHz (1.15ns). real attention cost is intrinsic, not repairable at 0.6
- X3Y2 area 87k um2, power halves at 1.2ns (236 -> 118 mW)
- X3Y3: 0.908 GHz but still FAILS 0.6 (32 viol, ws -0.501). staging cut viol 64->32, helped but not enough. critical path still originates in KV array read (kv_nibble_r/RN - the register-array read port itself)
- conclusion: unpacked register arrays for KV cache ARE the wall. this is exactly the X4 SRAM macro story - X3 freq ceiling confirmed architectural, not fixable by pipelining
- next: X4Y1 swap mla_kv_cache + kda_state to fakeram45 SRAM macros

## known gaps vs nano-kpu
- dims 4x small; register arrays not SRAM macros; MLA attention + conv + state update still cycle-counting (no MAC); no INT4 group-128 dequant; no functional/bit-exact verification
