#!/usr/bin/env python3
"""Exact comparison of RTL MLA tensors and KV-cache SRAM image (tb_mla.v dump)
with mla_model.int_step, plus the error of the fixed-point datapath against
the normative reference (reference/model.py RefModel._mla via nano_ref).

usage: golden_mla.py TRACE [--group G] [--wdir DIR] [--min-cos C]
Exit 0 only if every RTL value matches the bit-exact model, every PROBE saw a
full cache, and the reference cosine of every output row is >= --min-cos.
"""
import argparse, json, math, sys
import mla_model as mm

KEYS = ["hu", "latr", "lat", "latu", "qc", "qr", "kr", "kc", "v", "score", "p", "ctx", "ctxu", "out"]

def parse(path):
    toks = []
    for line in open(path):
        s = line.split()
        if s[0] == "TOKEN":
            toks.append(dict(kind="token", token=int(s[1]), seq_start=int(s[2]), cycles=int(s[3])))
        elif s[0] == "PROBE":
            toks.append(dict(kind="probe", token=int(s[1]), count=int(s[2])))
        elif s[0] == "m_kv":
            toks[-1]["kv"] = [None if any(c in w.lower() for c in "xz") else int(w, 16) for w in s[1:]]
        elif s[0].startswith("m_"):
            toks[-1][s[0][2:]] = [int(x) for x in s[1:]]
    return toks

def cos_err(a, b):
    a = [x / 65536 for x in a]
    na, nb = math.sqrt(sum(x * x for x in a)), math.sqrt(sum(float(y) ** 2 for y in b))
    cos = sum(x * float(y) for x, y in zip(a, b)) / (na * nb) if na and nb else float("nan")
    mx = max(abs(float(y)) for y in b)
    return cos, max(abs(x - float(y)) for x, y in zip(a, b)) / mx if mx else float("nan")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace"); ap.add_argument("--group", type=int, default=128)
    ap.add_argument("--wdir", default=None); ap.add_argument("--min-cos", type=float, default=0.999)
    ap.add_argument("--no-ref", action="store_true", help="skip the numpy reference comparison")
    a = ap.parse_args()
    W = mm.Weights(a.wdir, a.group) if a.wdir else mm.Weights(group=a.group)
    recs = parse(a.trace)
    toks = [r for r in recs if r["kind"] == "token"]
    refs = None
    if not a.no_ref:
        import nano_ref
        refs = iter(nano_ref.ref_mla_trace([(t["token"], t["seq_start"]) for t in toks], a.group))
    st = None
    rep = dict(tokens=[], probes=[], exact_match=True, ref_min_cos=None, ref_ok=True)
    def bad(msg):
        print("MISMATCH " + msg); rep["exact_match"] = False
    for n, t in enumerate(recs):
        if t["kind"] == "probe":
            full = st is not None and len(st["cache"]) == mm.MAX_SEQ
            rep["probes"].append(dict(token=t["token"], count=t["count"], model_full=full))
            if not full or t["count"] != mm.MAX_SEQ:
                bad(f"probe at record {n}: RTL count {t['count']}, model cache full={full}")
            continue
        if t["seq_start"] or st is None: st = mm.new_state()
        g = mm.int_step(W, st, t["token"])
        if [t["e"][0], t["e"][1], t["T"][0]] != [g["e_lat"], g["e_ctx"], g["T"]]:
            bad(f"record {n} token {t['token']} e/T: RTL={t['e'] + t['T']} model={[g['e_lat'], g['e_ctx'], g['T']]}")
        for key in KEYS:
            got, want = t[key], g[key]
            if got != want:
                i = next((i for i, (x, y) in enumerate(zip(got, want)) if x != y), -1)
                bad(f"record {n} token {t['token']} {key}[{i}]: RTL={got[i] if i >= 0 else len(got)} "
                    f"model={want[i] if i >= 0 else len(want)}")
        want_kv = mm.cache_words(st)
        if t["kv"] != want_kv:
            i = next((i for i, (x, y) in enumerate(zip(t["kv"], want_kv)) if x != y), -1)
            bad(f"record {n} token {t['token']} KV cache word {i} (entry {i // mm.WORDS}): "
                f"RTL={t['kv'][i] if i >= 0 else len(t['kv'])} model={want_kv[i] if i >= 0 else len(want_kv)}")
        row = dict(token=t["token"], seq_start=t["seq_start"], T=g["T"], cycles=t["cycles"],
                   e_lat=g["e_lat"], e_ctx=g["e_ctx"])
        if refs is not None:
            r = next(refs)
            assert r["T"] == g["T"]
            row["vs_reference"] = {k: dict(zip(("cos", "max_err_rel"), cos_err(g[k], r[k])))
                                   for k in ("lat", "p", "ctx", "out")}
            c = row["vs_reference"]["out"]["cos"]
            rep["ref_min_cos"] = c if rep["ref_min_cos"] is None else min(rep["ref_min_cos"], c)
            if not c >= a.min_cos: rep["ref_ok"] = False
        rep["tokens"].append(row)
    print(json.dumps(rep, indent=1))
    return 0 if rep["exact_match"] and rep["ref_ok"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
