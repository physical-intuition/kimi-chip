#!/usr/bin/env python3
from pathlib import Path
import sys, numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'golden'))
from kda_golden import kda_forward
V=ROOT/'tb'/'vectors';V.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(71)
x1=rng.integers(-48,49,128,dtype=np.int8);x2=x1.copy();x2[::5]=np.clip(x2[::5].astype(np.int16)+7,-128,127).astype(np.int8)
Ws=[rng.integers(-24,25,(128,128),dtype=np.int8) for _ in range(4)]
ca=rng.integers(-24,25,(128,4),dtype=np.int8);cb=rng.integers(-32,33,(128,4),dtype=np.int8)
S0=rng.integers(-12,13,(128,128),dtype=np.int8)
y1,S1=kda_forward(x1,*Ws,ca,cb,S0);y2,S2=kda_forward(x2,*Ws,ca,cb,S1)
def bits(x,w):return int(x)&((1<<w)-1)
def pack(vals,w):
 z=0
 for i,v in enumerate(vals):z|=bits(v,w)<<(i*w)
 return z
def wr(name,vals,width):
 d=(width+3)//4;(V/name).write_text(''.join(f'{int(v)&((1<<width)-1):0{d}x}\n' for v in vals))
wr('x1.mem',[pack(x1[i:i+16],8) for i in range(0,128,16)],128)
wr('x2.mem',[pack(x2[i:i+16],8) for i in range(0,128,16)],128)
# matrix-major logical 64-bit words; TB maps word 4*addr+bank.
wr('weights.mem',[pack(W.reshape(-1)[i:i+8],8) for W in Ws for i in range(0,16384,8)],64)
wr('state0.mem',[pack(S0.reshape(-1)[i:i+8],8) for i in range(0,16384,8)],64)
wr('state1.mem',[pack(S1.reshape(-1)[i:i+8],8) for i in range(0,16384,8)],64)
wr('state2.mem',[pack(S2.reshape(-1)[i:i+8],8) for i in range(0,16384,8)],64)
wr('conv_a.mem',[pack(ca[i],8) for i in range(128)],32);wr('conv_b.mem',[pack(cb[i],8) for i in range(128)],32)
wr('y1.mem',[pack(y1[i:i+16],8) for i in range(0,128,16)],128);wr('y2.mem',[pack(y2[i:i+16],8) for i in range(0,128,16)],128)
print('dependency output',np.count_nonzero(y1!=y2),'state',np.count_nonzero(S1!=S2))
assert np.any(y1!=y2) and np.any(S1!=S2)
