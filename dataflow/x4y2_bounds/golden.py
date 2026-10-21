#!/usr/bin/env python3
"""Independent streaming RTL arithmetic reference. None is an unknown word.
This verifies the IMPLEMENTED datapath, not missing KDA/MLA math.
"""
import argparse
import collections
import json
from pathlib import Path

def number(s):
    return None if any(c in s.lower() for c in "xz") else int(s, 16)

def plus(a, b, bits):
    return None if a is None or b is None else (a+b) & ((1<<bits)-1)

def sext24(x):
    return None if x is None else x | (0xff000000 if x & 0x800000 else 0)

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
        self.mem = [None]*2048
        self.bank_data = [None]*4
        self.bank = None
        self.count = 0
        self.accepted = collections.deque()
        self.phases = collections.Counter()
        self.writes = collections.Counter()
        self.unknown = collections.Counter()
        self.append_cycles = 0
        self.completed = 0
        self.cycles = 0

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
            self.accepted.append((tid+1)&511)
            if ss:
                self.count=0
        if p==12:
            self.append_cycles += 1
            if self.append_cycles == 32:
                self.count=(self.count+1)&255
                self.append_cycles=0
        self.check(c,"KV count next",newcount,self.count)
        if ce:
            bank,off=divmod(addr,512)
            old=self.mem[addr]
            self.bank_data[bank]=old
            self.bank=bank
            if we:
                self.mem[addr]=wd
                self.writes["sram"]+=1
        expected_rd=None if self.bank is None else self.bank_data[self.bank]
        self.check(c,"SRAM read-before-write/bank",rd,expected_rd)
        oldacc,olddone=self.mac.acc,self.mac.done
        expected_acc,expected_done=self.mac.step(start,a,b)
        self.check(c,"MAC accumulator",newacc,expected_acc)
        self.check(c,"MAC done",newdone,expected_done)
        if p in (1,2,3,10,13):
            self.pipe_v=olddone
            if olddone:
                self.pipe=oldacc
        self.check(c,"pipeline next data",newpipe,self.pipe)
        self.check(c,"pipeline next valid",newpv,self.pipe_v)
        if kind>=0:
            self.check(c,"projection/attention writeback",result,None if kind==10 and idx>=32 else sext24(pipe))
            self.writes[str(kind)]+=1
            if result is None:
                self.unknown[str(kind)]+=1
        if p==13 and (a is None or b is None):
            self.unknown["attention_operands"]+=1
        if ov:
            if not self.accepted:
                raise AssertionError(f"cycle {c}: unsolicited completion")
            self.check(c,"placeholder argmax",oid,self.accepted.popleft())
            self.completed+=1
        self.previous_phase=p

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
    assert all(ref.writes[str(p)] for p in (1,2,3,10,13)), "missing phase coverage"
    blockers=[
        "KDA state/convolution/output, normalization, residual and MLA B/output are placeholders",
        "argmax is token_id+1, not logits",
        "token embedding low INT4 nibbles are always zero",
        "MLA query has 32 elements but attention indexes 128",
        "weights and MAC accumulator persist across outputs/tokens; reset does not reload weights",
    ]
    report=dict(arithmetic_match=True,inference_verified=False,cycles=ref.cycles,
                completed_tokens=ref.completed,phase_cycles=dict(ref.phases),
                writes=dict(ref.writes),unknowns=dict(ref.unknown),blockers=blockers)
    if args.report:
        args.report.write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))
    return 0 if args.diagnostic else 2

if __name__=="__main__":
    raise SystemExit(main())
