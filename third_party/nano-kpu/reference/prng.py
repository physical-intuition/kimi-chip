"""Deterministic PRNG for test-vector and synthetic-weight generation.

splitmix64 is the normative generator. It is fully specified here and does
not depend on numpy's random module (whose streams are not guaranteed stable
across versions). All quantities in the evaluation that are "random" derive
from (global_seed, stream_name) through this file.
"""

import numpy as np

_M64 = np.uint64(0xFFFFFFFFFFFFFFFF)
_GAMMA = np.uint64(0x9E3779B97F4A7C15)
_C1 = np.uint64(0xBF58476D1CE4E5B9)
_C2 = np.uint64(0x94D049BB133111EB)


def fnv1a64(s: str) -> int:
    """FNV-1a 64-bit hash of a UTF-8 string."""
    h = 0xCBF29CE484222325
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def stream_seed(global_seed: int, name: str) -> int:
    return (global_seed ^ fnv1a64(name)) & 0xFFFFFFFFFFFFFFFF


def splitmix64_array(seed: int, n: int) -> np.ndarray:
    """First n outputs of splitmix64 seeded with `seed`, as uint64."""
    idx = np.arange(1, n + 1, dtype=np.uint64)
    with np.errstate(over="ignore"):
        x = np.uint64(seed) + idx * _GAMMA
        z = (x ^ (x >> np.uint64(30))) * _C1
        z = (z ^ (z >> np.uint64(27))) * _C2
        z = z ^ (z >> np.uint64(31))
    return z


def rand_u64(global_seed: int, name: str, n: int) -> np.ndarray:
    return splitmix64_array(stream_seed(global_seed, name), n)


def rand_int_range(global_seed: int, name: str, n: int, lo: int, hi: int) -> np.ndarray:
    """Uniform integers in [lo, hi] via modulo (modulo bias is accepted and
    part of the spec; ranges used here are far below 2^64). Chunked to bound
    peak memory on very large tensors; chunking does not affect the values."""
    seed = stream_seed(global_seed, name)
    span = np.uint64(hi - lo + 1)
    out = np.empty(n, dtype=np.int64)
    step = 1 << 24
    for off in range(0, n, step):
        m = min(step, n - off)
        idx = np.arange(off + 1, off + m + 1, dtype=np.uint64)
        with np.errstate(over="ignore"):
            x = np.uint64(seed) + idx * _GAMMA
            z = (x ^ (x >> np.uint64(30))) * _C1
            z = (z ^ (z >> np.uint64(27))) * _C2
            z = z ^ (z >> np.uint64(31))
        out[off:off + m] = (z % span).astype(np.int64) + lo
    return out
