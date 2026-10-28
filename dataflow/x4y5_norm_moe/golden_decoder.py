#!/usr/bin/env python3
"""X4Y5: exact comparison of the RTL decoder trace (tb_decoder.v dump) with
decoder_model.int_step -- every KDA tensor, every MLA tensor + KV-cache SRAM image,
and every glue vector (x0, RMSNorm outputs, residual mixes, MoE router logits,
selection, weights, outputs, residual adds). Then the float distance of L0.out /
L1.out to reference/model.py RefModel.step (same staged x0).

Exit 0 only if every RTL value equals the model and every reference cosine passes:
cos >= --min-cos, or the token is a documented MoE top-k flip (reference selection
keys of the two swapped experts within --tie of each other)."""
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
    return e

def cos(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace"); ap.add_argument("--group", type=int, default=128)
    ap.add_argument("--wdir", default=None)
    ap.add_argument("--min-cos", type=float, default=0.99)
    ap.add_argument("--tie", type=float, default=2e-3)
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
        mins = dict(L0=1.0, L1=1.0)
        for row, g, ref in zip(rep["tokens"], gs, refs):
            c0 = cos(np.asarray(g["x1"]) / 65536, ref["L0.out"]); c1 = cos(np.asarray(g["x2"]) / 65536, ref["L1.out"])
            row.update(cos_L0=round(c0, 6), cos_L1=round(c1, 6))
            for li, c, moe in ((0, c0, g["moe0"]), (1, c1, g["moe1"])):
                rsel = ref[f"L{li}.moe.sel"][:2].astype(int).tolist()
                if c >= a.min_cos:
                    mins[f"L{li}"] = min(mins[f"L{li}"], c); continue
                key = ref[f"L{li}.moe.key"]
                diff = sorted(set(rsel) ^ set(moe["sel"]))
                flip = len(diff) == 2 and abs(key[diff[0]] - key[diff[1]]) < a.tie
                row.setdefault("topk_flip", []).append(dict(layer=li, cos=round(c, 6), ref_sel=rsel, int_sel=moe["sel"],
                    ref_key_gap=round(float(abs(key[diff[0]] - key[diff[1]])), 6) if len(diff) == 2 else None))
                if not flip:
                    print(f"REF FAIL token {row['token']} L{li}.out cos {c:.5f} (sel ref {rsel} int {moe['sel']})")
                    rep["ref_ok"] = False
        rep["min_cos_excluding_flips"] = {k: round(v, 6) for k, v in mins.items()}
        rep["topk_flips"] = sum(len(t.get("topk_flip", [])) for t in rep["tokens"])
    print(json.dumps(dict(exact_match=rep["exact_match"], ref_ok=rep["ref_ok"], tokens=len(rep["tokens"]),
                          probes=rep["probes"], min_cos=rep.get("min_cos_excluding_flips"),
                          flips=[dict(token=t["token"], **f) for t in rep["tokens"] for f in t.get("topk_flip", [])],
                          cycles=[t["cycles"] for t in rep["tokens"]][:8])))
    return 0 if rep["exact_match"] and rep["ref_ok"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
