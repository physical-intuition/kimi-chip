#!/usr/bin/env python3
"""Exact comparison of RTL KDA tensors (tb_kda.v dump) with kda_model.int_step,
plus float64 approximation error. Exit 0 only if every value matches."""
import json, sys
import kda_model as m

def parse(path):
    toks, cur = [], None
    for line in open(path):
        s = line.split()
        if s[0] == "PROBE" or s[0].startswith("m_"): continue   # X4Y4: MLA records (golden_mla.py)
        if s[0] == "TOKEN":
            cur = dict(token=int(s[1]), seq_start=int(s[2]), cycles=int(s[3])); toks.append(cur)
        else:
            cur[s[0]] = [int(x) for x in s[1:]]
    return toks

def main():
    toks = parse(sys.argv[1])
    st = fs = None
    report = dict(tokens=[], exact_match=True)
    for n, t in enumerate(toks):
        if t["seq_start"] or st is None:
            st, fs = m.new_state(), m.float_new_state()
        g = m.int_step(st, t["token"]); f = m.float_step(fs, t["token"])
        exp = dict(q=g["q"], k=g["k"], v=g["v"], alpha=g["alpha"], f=g["f"], z=g["z"],
                   attn=g["attn"], y=g["y"], out=g["out"], beta=g["beta"],
                   hist=[x for tap in g["hist"] for x in tap],
                   S=[x for Sh in g["S"] for row in Sh for x in row])
        for key, want in exp.items():
            got = t[key]
            if got != want:
                bad = next(i for i, (a, b) in enumerate(zip(got, want)) if a != b) if len(got) == len(want) else -1
                print(f"MISMATCH token#{n} ({t['token']}) {key}[{bad}]: RTL={got[bad] if bad>=0 else len(got)} golden={want[bad] if bad>=0 else len(want)}")
                report["exact_match"] = False
        Sf = [x for Sh in f["S"] for row in Sh for x in row]
        def err(a, b): return max(abs(x / 65536 - y) for x, y in zip(a, b))
        report["tokens"].append(dict(token=t["token"], seq_start=t["seq_start"], cycles=t["cycles"],
            max_abs_err=dict(q=err(g["q"], f["q"]), k=err(g["k"], f["k"]), S=err(exp["S"], Sf),
                             attn=err(g["attn"], f["attn"]), y=err(g["y"], f["y"])),
            max_abs=dict(S=max(abs(x) for x in Sf), y=max(abs(x) for x in f["y"])),
            nonzero_S=sum(1 for x in exp["S"] if x)))
    print(json.dumps(report, indent=1))
    return 0 if report["exact_match"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
