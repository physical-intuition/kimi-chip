"""Nano-only model config. This task is a single-size instance of the Moonshot
hybrid text architecture: repeating [KDA, KDA, KDA, MLA] token-mixer blocks
(Kimi Delta Attention linear layers + one NoPE multi-head latent attention
layer per block), fine-grained sigmoid-routed MoE MLPs with one shared
expert, attention-residual mixing (block size 2), RMSNorm, untied int4
embedding / LM head. There is no positional encoding anywhere — KDA's
decaying state carries position.

The nano config is evaluated teacher-forced on two token sequences of different
lengths (`seq_lens`) — long contexts exercise the KV cache and KDA state,
short ones the pipeline ramp (under stressed memory timing; see
docs/interface.md). The harness may scale sequence lengths (seeds file
`seq_stretch`, bounded by `max_seq`) and may select `group_size` 64 or 128
— read the header, do not bake in the public values.
"""

import json
import os
from dataclasses import dataclass, asdict

# Architecture constants shared by the nano task (documented in
# docs/architecture.md; NOT in the image header — they never vary):
RMS_EPS = 1e-5          # RMSNorm epsilon (all norms)
L2_EPS = 1e-6           # L2-norm epsilon (KDA q/k)
KDA_GATE_LOWER_BOUND = -5.0   # per-channel log-decay lower bound
ROUTER_SCALE = 2.828    # routed-expert weight scaling factor (~2*sqrt(2))


@dataclass
class ModelConfig:
    name: str
    d_model: int
    n_layers: int
    layer_pattern: str          # e.g. "LLLF"; len must divide n_layers
    # full attention (MLA, NoPE: nothing is rotated)
    n_heads: int
    mla_dk: int                 # per-head main q/k dim
    mla_dr: int                 # per-head extra q/k dim (shared k, unrotated)
    mla_dv: int                 # per-head v dim
    mla_dc: int                 # compressed kv latent dim
    # linear attention (KDA)
    kda_heads: int
    kda_dim: int                # per-head q/k/v dim (= low-rank width)
    conv_kernel: int
    # MoE
    n_experts: int
    top_k: int
    n_shared: int
    d_ff: int                   # per-expert SwiGLU intermediate size
    # residual mixing / embedding / quantization
    attn_res_block: int         # attention-residual block size
    vocab: int
    max_seq: int
    group_size: int             # int4 quant group along fan_in (clamped)
    # evaluation parameters
    seq_lens: tuple             # (long, short) teacher-forced lengths
    timeout_cycles: int
    wall_secs: int = 600

    def __post_init__(self):
        assert self.n_layers % len(self.layer_pattern) == 0
        assert self.n_shared == 1, "spec restriction: one shared expert"
        assert self.top_k <= self.n_experts
        # int4 packs 2 values/byte along fan_in: every fan_in must be even
        for fan_in in (self.d_model, self.mla_dc, self.kda_dim,
                       self.kda_heads * self.kda_dim,
                       self.n_heads * self.mla_dv, self.d_ff):
            assert fan_in % 2 == 0
        assert all(s <= self.max_seq for s in self.seq_lens)

    @property
    def layer_types(self):
        pat = self.layer_pattern * (self.n_layers // len(self.layer_pattern))
        return list(pat)


CONFIGS = {
    "nano": ModelConfig(
        name="nano", d_model=64, n_layers=2, layer_pattern="LF",
        n_heads=2, mla_dk=32, mla_dr=16, mla_dv=32, mla_dc=128,
        kda_heads=2, kda_dim=32, conv_kernel=4,
        n_experts=8, top_k=2, n_shared=1, d_ff=32,
        attn_res_block=2, vocab=512, max_seq=64, group_size=128,
        seq_lens=(48, 16), timeout_cycles=300_000_000, wall_secs=450),
}

# Single-size task: correctness and performance are both measured on nano.
LADDER = [("nano", 1.0)]
DEFAULT_LADDER = ["nano"]
PERF_CONFIGS = ["nano"]


def dump_json(path: str):
    with open(path, "w") as f:
        json.dump({k: asdict(v) for k, v in CONFIGS.items()}, f, indent=2)


if __name__ == "__main__":
    dump_json(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "configs.json"))
    for n, c in CONFIGS.items():
        print(f"{n}: layers={''.join(c.layer_types)} experts={c.n_experts} "
              f"seq_lens={c.seq_lens}")
