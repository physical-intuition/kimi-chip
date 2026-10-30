#!/usr/bin/env python3
"""Independent streaming RTL arithmetic reference + X4Y6 strict inference gate. None is an unknown word.
This verifies the IMPLEMENTED datapath cycle by cycle (shared MAC, SRAM, protocol).
KDA, MLA and glue math is verified separately and exactly by golden_decoder.py
(tb_decoder.v dump vs decoder_model); here the operator
phases only drive the MAC and the KV-cache SRAM, whose bounds are checked.
X4Y4: KV cache = 9 x 512-word banks, 72 words per entry, append in phase 12,
reads in phases 13 (keys) and 15 (values); the legacy pipe register is inert.
"""
import argparse
import collections
import json
import decoder_model as dm
from pathlib import Path

WORDS, BANK, NBANK, MAX_SEQ = 72, 512, 9, 64
MLA_NOUT = {9: 128, 10: 64, 11: 32, 12: 16, 13: 64, 14: 64, 15: 64}

def number(s):
    return None if any(c in s.lower() for c in "xz") else int(s, 16)

def plus(a, b, bits):
    return None if a is None or b is None else (a+b) & ((1<<bits)-1)

class Mac:
    """Unsigned INT4; fold each 16 products; wrap 12/24 bits.
    Pipeline modeled as a queue, not copied partial-product RTL.
    """
    def __init__(self):
        self.pending = collections.deque([(False, 0, False)]*2)
        self.count = self.fast = self.acc = self.done = 0

    def step(self, start, a, b):
        product = 0 if a == 0 or b == 0 else (None if a is None or b is None else a*b)
        item = (bool(start), product,
                bool(start and self.count == 15))
        if start:
            self.count = (self.count+1) % 16
        valid, product, fold = self.pending.popleft()
        self.pending.append(item)
        self.done = int(valid and fold)
        if valid:
            if fold:
                self.acc = plus(plus(self.acc, self.fast, 24), product, 24)
                self.fast = 0
            else:
                self.fast = plus(self.fast, product, 12)
        return self.acc, self.done

class Reference:
    def __init__(self):
        self.mac = Mac()
        self.pipe = self.pipe_v = 0
        self.mem = [None]*(BANK*NBANK)
        self.bank_data = [None]*NBANK
        self.bank = None
        self.count = 0
        self.accepted = collections.deque()
        self.model_w = dm.Weights(); self.model_state = None
        self.phases = collections.Counter()
        self.writes = collections.Counter()
        self.unknown = collections.Counter()
        self.sram = collections.Counter()
        self.append_cycles = 0
        self.completed = 0
        self.cycles = 0
        self.previous_phase = 0
        self.previous_count = 0
        self.token_writes = collections.Counter()

    def check(self, cycle, field, actual, expected):
        if actual != expected:
            raise AssertionError(f"cycle {cycle} {field}: RTL={actual!r} golden={expected!r}")

    def row(self, line):
        s=line.split()
        c,p=int(s[0]),int(s[1])
        vals=list(map(number,s[2:18]))
        (start,a,b,done,acc,pv,pipe,ce,we,addr,wd,tv,ss,tid,count,layer)=vals
        kind,idx=int(s[18]),int(s[19])
        (newacc,newdone,newpipe,newpv,rd,result,ov,oid,newcount)=map(number,s[20:])
        self.cycles=c
        self.phases[p]+=1
        self.check(c,"MAC previous accumulator",acc,self.mac.acc)
        self.check(c,"MAC previous done",done,self.mac.done)
        self.check(c,"pipeline data",pipe,self.pipe)
        self.check(c,"pipeline valid",pv,self.pipe_v)
        self.check(c,"KV count",count,self.count)
        if tv and p==0:
            # X4Y6: the argmax port must equal the bit-exact model's argmax over the 512 logits
            if ss or self.model_state is None: self.model_state = dm.new_state()
            self.accepted.append(dm.int_step(self.model_w, self.model_state, tid)["argmax"])
            if ss:
                self.count=0
        if p==12:
            self.append_cycles += 1
            if self.append_cycles == WORDS:
                self.count=(self.count+1)&255
                self.append_cycles=0
        self.check(c,"KV count next",newcount,self.count)
        if ce:
            # controls seen now were issued last cycle (previous phase / count)
            if addr is None:
                raise AssertionError(f"cycle {c}: unknown SRAM address")
            if we:
                if self.previous_phase != 12 or addr // WORDS != self.previous_count \
                        or self.previous_count >= MAX_SEQ:
                    raise AssertionError(f"cycle {c}: SRAM write {addr} outside append of entry {self.previous_count}")
                self.sram["writes"]+=1
            else:
                if self.previous_phase not in (13, 15):
                    raise AssertionError(f"cycle {c}: SRAM read outside attention (phase {self.previous_phase})")
                if addr >= self.previous_count*WORDS:
                    raise AssertionError(f"cycle {c}: read of invalid cache word {addr} (count {self.previous_count})")
                self.sram["reads"]+=1
            bank,off=divmod(addr,BANK)
            old=self.mem[addr]
            self.bank_data[bank]=old
            self.bank=bank
            if we:
                self.mem[addr]=wd
        expected_rd=None if self.bank is None else self.bank_data[self.bank]
        self.check(c,"SRAM read-before-write/bank",rd,expected_rd)
        expected_acc,expected_done=self.mac.step(start,a,b)
        self.check(c,"MAC accumulator",newacc,expected_acc)
        self.check(c,"MAC done",newdone,expected_done)
        self.check(c,"pipeline next data",newpipe,self.pipe)
        self.check(c,"pipeline next valid",newpv,self.pipe_v)
        if start and (a is None or b is None):
            self.unknown["mac_operands"]+=1
        if kind>=9:
            if idx >= MLA_NOUT[kind]:
                raise AssertionError(f"cycle {c}: MLA matrix {kind} output index {idx}")
            if result is None:
                self.unknown[f"mla_writeback_{kind}"]+=1
            self.writes[str(kind)]+=1
            self.token_writes[kind]+=1
        if ov:
            if not self.accepted:
                raise AssertionError(f"cycle {c}: unsolicited completion")
            self.check(c,"argmax",oid,self.accepted.popleft())
            for m, n in MLA_NOUT.items():
                self.check(c,f"MLA matrix {m} writebacks this token",self.token_writes[m],n)
            self.token_writes.clear()
            self.completed+=1
        self.previous_phase=p
        self.previous_count=count

BAR = 0.98   # reference/model.py: "pass bar: cos >= 0.98 on every row"

def inference_check():
    """Teacher-forced public prompts through decoder_model.int_step (== the RTL, see
    run_decoder.sh), per-row logits cosine vs RefModel.step on the fully official
    weights (the normative check) and vs the same reference with the X4Y3 KDA
    placeholders substituted (what the RTL implements)."""
    import numpy as np
    import nano_ref
    W = dm.Weights()
    def run(official):
        rows = []
        for toks in nano_ref.public_tokens():
            seq = [(t, i == 0) for i, t in enumerate(toks)]
            st = dm.new_state(); ints = [dm.int_step(W, st, t) for t in toks]
            for g, r in zip(ints, nano_ref.ref_decoder_trace(seq, official_kda=official)):
                L = np.asarray(g["logits"], float) / 65536; rl = r["logits"]
                rows.append((float(L @ rl / np.linalg.norm(L) / np.linalg.norm(rl)), g["argmax"] == int(np.argmax(rl))))
        cs = [c for c, _ in rows]
        return dict(rows=len(rows), min_cos=round(min(cs), 5), mean_cos=round(float(np.mean(cs)), 5),
                    argmax_agree=sum(a for _, a in rows),
                    rows_below_bar=[(i, round(c, 5)) for i, (c, _) in enumerate(rows) if c < BAR])
    out = run(True)
    out["placeholder_ref"] = run(False)
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("trace",type=Path)
    ap.add_argument("--diagnostic",action="store_true",
                    help="permit known architectural blockers, never inference signoff")
    ap.add_argument("--report",type=Path)
    args=ap.parse_args()
    ref=Reference()
    with args.trace.open() as f:
        for line in f:
            ref.row(line)
    assert ref.completed==3 and not ref.accepted, "missing token completion"
    assert all(ref.writes[str(m)] for m in MLA_NOUT), "missing MLA projection coverage"
    assert all(ref.phases[p] for p in (1,2,3,4,5,6,7,8,9,20)), "missing KDA phase coverage"
    assert all(ref.phases[p] for p in (10,11,12,13,14,15,21,22,23)), "missing MLA phase coverage"
    assert not ref.unknown, f"unknown values: {dict(ref.unknown)}"
    assert ref.phases[24], "missing X4Y5 glue (norm / residual mixing / MoE) phase coverage"
    inf = inference_check()
    blockers=[]
    if inf["rows_below_bar"]:
        blockers.append(
            f"inference vs the normative reference fails the model.py bar (logits cosine >= {BAR} on every row): "
            f"{len(inf['rows_below_bar'])}/{inf['rows']} public-prompt rows below, min cosine {inf['min_cos']}, "
            f"argmax agreement {inf['argmax_agree']}/{inf['rows']}. Main cause: KDA weights are X4Y3 placeholders "
            "(fixed z=8, s=2^-6) instead of the official L0.kda tensors; against a reference that substitutes the same "
            f"placeholders the min cosine is {inf['placeholder_ref']['min_cos']} "
            f"({len(inf['placeholder_ref']['rows_below_bar'])} rows below, all MoE expert-selection differences)")
    blockers.append("MLA, MoE, embedding, head, norm and mixing weights are official seeded synthetic tensors held "
                    "in on-chip ROM, not streamed from the memory image; chip interface (msh_chip_top, memory port, "
                    "image header, msh_sram macros) not implemented")
    report=dict(arithmetic_match=True,inference_verified=not inf["rows_below_bar"],inference=inf,cycles=ref.cycles,
                completed_tokens=ref.completed,phase_cycles=dict(ref.phases),
                writes=dict(ref.writes),sram=dict(ref.sram),unknowns=dict(ref.unknown),
                blockers=blockers)
    if args.report:
        args.report.write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))
    return 0 if args.diagnostic or not blockers else 2

if __name__=="__main__":
    raise SystemExit(main())
