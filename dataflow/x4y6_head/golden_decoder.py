#!/usr/bin/env python3
"""X4Y6: exact comparison of the RTL decoder trace (tb_decoder.v dump) with
decoder_model.int_step -- every KDA tensor, every MLA tensor + KV-cache SRAM image,
and every glue vector (x0 = embedding row, RMSNorm outputs, residual mixes, MoE
router logits, selection, weights, outputs, residual adds, res_out mix, final norm),
the LM-head codes, all 512 logits and the argmax output port. Then the float
distance to reference/model.py RefModel.step (official embedding, X4Y3 KDA
placeholder weights = what the RTL implements): per-row cosine of the logits
(headline, bar 0.98 from model.py), L0.out / L1.out, MoE selection differences and
argmax differences.

Exit 1 if any RTL value differs from the model. Rows below the bar are always
reported; they fail only with --ref-strict."""
import argparse, json, math, sys
import numpy as np
import decoder_model as dm, mla_model as mm

KDA_KEYS = ["q", "k", "v", "alpha", "f", "z", "attn", "y", "out", "beta", "hist", "S"]
MLA_KEYS = ["hu", "latr", "lat", "latu", "qc", "qr", "kr", "kc", "v", "score", "p", "ctx", "ctxu", "out"]

def parse(path):
    toks = []
    for line in open(path):
        s = line.split()
        if not s: continue
        if s[0] == "TOKEN":
            toks.append(dict(kind="token", token=int(s[1]), seq_start=int(s[2]), cycles=int(s[3])))
        elif s[0] == "PROBE":
            toks.append(dict(kind="probe", token=int(s[1]), count=int(s[2])))
        elif s[0] == "m_kv":
            toks[-1]["m_kv"] = [None if any(c in w.lower() for c in "xz") else int(w, 16) for w in s[1:]]
        else:   # KDA dumps are unprefixed (X4Y4 tb_mla.v format)
            toks[-1][("k_" + s[0]) if s[0] in KDA_KEYS else s[0]] = [int(x) for x in s[1:]]
    return toks

def expected(g, st):
    k, m = g["kda"], g["mla"]
    e = {"k_" + n: k[n] for n in KDA_KEYS[:-3]}
    e["k_beta"] = k["beta"]
    e["k_hist"] = [x for tap in k["hist"] for x in tap]
    e["k_S"] = [x for Sh in k["S"] for row in Sh for x in row]
    for n in MLA_KEYS: e["m_" + n] = m[n]
    e["m_e"] = [m["e_lat"], m["e_ctx"]]; e["m_T"] = [m["T"]]
    e["m_kv"] = mm.cache_words(st["mla"])
    e["g_slots"] = [v for key in ("x0", "h0", "a0") for v in g[key]] + g["mix0"]["out"] + g["h0b"] + \
        g["moe0"]["out"] + g["x1"] + g["mix1"]["out"] + g["h1"] + g["mla"]["out"] + g["pre"] + \
        g["mix2"]["out"] + g["h2"] + g["moe1"]["out"] + g["x2"]
    e["g_e"] = [g["kda_e"], g["kda"]["ey"], g["mla_e"], g["moe0"]["e"], g["moe1"]["e"]]
    e["g_sel"] = g["moe0"]["sel"] + g["moe1"]["sel"]
    e["g_w"] = g["moe0"]["w"] + g["moe1"]["w"]
    e["g_r"] = g["moe0"]["r"] + g["moe1"]["r"]
    e["g_logit"] = g["mix0"]["logits"] + g["mix1"]["logits"] + g["mix2"]["logits"]
    e["g_p"] = g["mix0"]["p"] + g["mix1"]["p"] + g["mix2"]["p"]
    # X4Y6
    e["g_logit"] += g["mix3"]["logits"]; e["g_p"] += g["mix3"]["p"]
    e["g_out"] = g["mix3"]["out"] + g["hn"]
    e["h_e"] = [g["head_e"]]; e["h_u"] = g["head_u"]
    e["h_logits"] = g["logits"]; e["h_argmax"] = [g["argmax"]]
    return e

def cos(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace"); ap.add_argument("--group", type=int, default=128)
    ap.add_argument("--wdir", default=None)
    ap.add_argument("--bar", type=float, default=0.98, help="per-row logits cosine bar (reference/model.py)")
    ap.add_argument("--ref-strict", action="store_true", help="fail if any row is below --bar")
    ap.add_argument("--no-ref", action="store_true")
    a = ap.parse_args()
    W = dm.Weights(a.wdir, a.group) if a.wdir else dm.Weights(group=a.group)
    recs = parse(a.trace)
    toks = [r for r in recs if r["kind"] == "token"]
    rep = dict(tokens=[], probes=[], exact_match=True, ref_ok=True)
    def bad(msg):
        print("MISMATCH " + msg); rep["exact_match"] = False
    st = None
    seq, gs = [], []
    for n, r in enumerate(recs):
        if r["kind"] == "probe":
            rep["probes"].append(dict(token=r["token"], count=r["count"]))
            if r["count"] != mm.MAX_SEQ: bad(f"probe record {n}: RTL count {r['count']} != {mm.MAX_SEQ}")
            continue
        if r["seq_start"] or st is None: st = dm.new_state()
        g = dm.int_step(W, st, r["token"])
        for key, want in expected(g, st).items():
            got = r.get(key)
            if got != want:
                if got is None or len(got) != len(want):
                    bad(f"record {n} token {r['token']} {key}: length RTL={None if got is None else len(got)} model={len(want)}")
                else:
                    i = next(i for i, (x, y) in enumerate(zip(got, want)) if x != y)
                    bad(f"record {n} token {r['token']} {key}[{i}]: RTL={got[i]} model={want[i]}")
        seq.append((r["token"], r["seq_start"])); gs.append(g)
        rep["tokens"].append(dict(token=r["token"], seq_start=r["seq_start"], cycles=r["cycles"],
                                  sel=[g["moe0"]["sel"], g["moe1"]["sel"]]))
    if not a.no_ref:
        import nano_ref
        refs = nano_ref.ref_decoder_trace(seq, a.group)
        rows_below, aflips, cl, mins = [], [], [], dict(L0=1.0, L1=1.0)
        for n, (row, g, ref) in enumerate(zip(rep["tokens"], gs, refs)):
            c0 = cos(np.asarray(g["x1"]) / 65536, ref["L0.out"]); c1 = cos(np.asarray(g["x2"]) / 65536, ref["L1.out"])
            L = np.asarray(g["logits"]) / 65536; rl = ref["logits"]
            cL = cos(L, rl); cl.append(cL)
            mins["L0"] = min(mins["L0"], c0); mins["L1"] = min(mins["L1"], c1)
            row.update(cos_L0=round(c0, 6), cos_L1=round(c1, 6), cos_logits=round(cL, 6))
            for li, moe in ((0, g["moe0"]), (1, g["moe1"])):
                rsel = ref[f"L{li}.moe.sel"][:2].astype(int).tolist()
                if set(rsel) != set(moe["sel"]):
                    key = ref[f"L{li}.moe.key"]; diff = sorted(set(rsel) ^ set(moe["sel"]))
                    row.setdefault("topk_flip", []).append(dict(layer=li, ref_sel=rsel, int_sel=moe["sel"],
                        ref_key_gap=round(float(abs(key[diff[0]] - key[diff[1]])), 6) if len(diff) == 2 else None))
            ra = int(np.argmax(rl))   # reference argmax (np.argmax: lowest index on ties)
            if g["argmax"] != ra:
                top = np.sort(rl)[::-1]
                aflips.append(dict(index=n, token=row["token"], int_argmax=g["argmax"], ref_argmax=ra,
                                   ref_top2_gap=round(float(top[0] - top[1]), 5),
                                   ref_logit_of_int_argmax=round(float(rl[g["argmax"]]), 5)))
            if cL < a.bar:
                rows_below.append(dict(index=n, token=row["token"], cos_logits=round(cL, 6), cos_L1=round(c1, 6),
                                       topk_flip=row.get("topk_flip", [])))
        rep.update(min_cos_logits=round(min(cl), 6), mean_cos_logits=round(float(np.mean(cl)), 6),
                   min_cos=dict({k: round(v, 6) for k, v in mins.items()}, logits=round(min(cl), 6)),
                   rows_below_bar=rows_below, argmax_flips=aflips,
                   topk_flips=[dict(index=i, token=t["token"], **f) for i, t in enumerate(rep["tokens"]) for f in t.get("topk_flip", [])])
        # Rows below the model.py bar are never excused here; --ref-strict turns them into a failure.
        rep["ref_ok"] = not rows_below
        if not rows_below: pass
        elif a.ref_strict:
            for r in rows_below: print(f"REF FAIL index {r['index']} token {r['token']} logits cos {r['cos_logits']:.5f}")
    print(json.dumps(dict(exact_match=rep["exact_match"], ref_ok=rep["ref_ok"], tokens=len(rep["tokens"]),
                          probes=rep["probes"], min_cos=rep.get("min_cos"), mean_cos_logits=rep.get("mean_cos_logits"),
                          rows_below_bar=rep.get("rows_below_bar"), argmax_flips=rep.get("argmax_flips"),
                          topk_flips=rep.get("topk_flips"), cycles=[t["cycles"] for t in rep["tokens"]][:8])))
    if not rep["exact_match"]: return 1
    return 1 if (a.ref_strict and not rep["ref_ok"]) else 0

if __name__ == "__main__":
    raise SystemExit(main())
