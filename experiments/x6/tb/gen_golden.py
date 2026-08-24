#!/usr/bin/env python3
"""Generate deterministic little-lane-first vectors for the X6 Y3 RTL tests."""
from __future__ import annotations

from math import isqrt, sqrt
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VEC = ROOT / "vectors"
VEC.mkdir(parents=True, exist_ok=True)


def bits(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def signed(value: int, width: int) -> int:
    value &= (1 << width) - 1
    return value - (1 << width) if value & (1 << (width - 1)) else value


def sat(value: int, width: int) -> int:
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    return min(max(value, lo), hi)


def pack(values: list[int], width: int) -> int:
    word = 0
    for lane, value in enumerate(values):
        word |= bits(value, width) << (lane * width)
    return word


def write_hex(name: str, values: list[int], width: int) -> None:
    digits = (width + 3) // 4
    (VEC / name).write_text("".join(f"{value & ((1 << width) - 1):0{digits}x}\n" for value in values))


# MAC: eight 16-output tiles, each consuming eight 16-activation beats.
x = [((i * 7) % 31) - 15 for i in range(128)]
mac_activation = [pack(x[b * 16:(b + 1) * 16], 8) for b in range(8)]
mac_weight_beats: list[int] = []
mac_golden: list[int] = []
for tile in range(8):
    flat: list[int] = []
    outputs: list[int] = []
    for r in range(128):
        for c in range(16):
            out = tile * 16 + c
            w = 1 if r == out else (-1 if r == ((out + 1) % 128) else 0)
            flat.append(w)
    for beat in range(32):
        mac_weight_beats.append(pack(flat[beat * 64:(beat + 1) * 64], 4))
    for c in range(16):
        out = tile * 16 + c
        outputs.append(sat(x[out] - x[(out + 1) % 128], 24))
    mac_golden.append(pack(outputs, 24))
write_hex("mac_activation.mem", mac_activation, 128)
write_hex("mac_weights.mem", mac_weight_beats, 256)
write_hex("mac_golden.mem", mac_golden, 384)


# State update: nontrivial signed values, pass-1 A/u and pass-2 S_new/q_out.
state_rows: list[int] = []
scaled_rows: list[int] = []
updated_rows: list[int] = []
alpha_values: list[int] = []
k_values: list[int] = []
q_values: list[int] = []
delta = [((j % 9) - 4) * 16 for j in range(128)]
u = [0] * 128
qout = [0] * 128
for i in range(128):
    alpha = 64 + (i % 4) * 8
    k = ((i % 7) - 3) * 4
    q = ((i % 5) - 2) * 3
    alpha_values.append(bits(alpha, 8))
    k_values.append(bits(k, 8))
    q_values.append(bits(q, 8))
    row = [((i * 3 + j * 5) % 31) - 15 for j in range(128)]
    a = [sat((value * alpha) >> 7, 24) for value in row]
    new = [sat(a[j] + ((delta[j] * k) >> 7), 24) for j in range(128)]
    for j in range(128):
        u[j] = sat(u[j] + ((a[j] * k) >> 7), 24)
        qout[j] = sat(qout[j] + ((new[j] * q) >> 7), 24)
    state_rows.append(pack(row, 24))
    scaled_rows.append(pack(a, 24))
    updated_rows.append(pack(new, 24))
write_hex("state_rows.mem", state_rows, 3072)
write_hex("state_scaled.mem", scaled_rows, 3072)
write_hex("state_updated.mem", updated_rows, 3072)
write_hex("state_alpha.mem", alpha_values, 8)
write_hex("state_k.mem", k_values, 8)
write_hex("state_q.mem", q_values, 8)
write_hex("state_delta.mem", [pack(delta, 24)], 3072)
write_hex("state_u.mem", [pack(u, 24)], 3072)
write_hex("state_qout.mem", [pack(qout, 24)], 3072)


# Convolution: eight beats cover 128 channels. Golden values match the documented PWL gates.
def sigmoid_pwl(value: int) -> int:
    return 0 if value <= -512 else 127 if value >= 512 else 64 + (value >> 3)


def tanh_pwl(value: int) -> int:
    return -127 if value <= -256 else 127 if value >= 256 else value >> 1

conv_history: list[int] = []
conv_aw: list[int] = []
conv_bw: list[int] = []
conv_ab: list[int] = []
conv_bb: list[int] = []
conv_alpha_golden: list[int] = []
conv_beta_golden: list[int] = []
true_sigmoid_error = 0.0
true_tanh_error = 0.0
for beat in range(8):
    history: list[int] = []
    aw: list[int] = []
    bw: list[int] = []
    abias: list[int] = []
    bbias: list[int] = []
    alpha_out: list[int] = []
    beta_out: list[int] = []
    for lane in range(16):
        channel = beat * 16 + lane
        hs = [((channel + tap * 3) % 17) - 8 for tap in range(4)]
        aws = [1, -2, 2, -1]
        bws = [-1, 1, 1, -1]
        ai = (channel % 7 - 3) * 16
        bi = (channel % 5 - 2) * 24
        asum = ai + sum(a * b for a, b in zip(hs, aws))
        bsum = bi + sum(a * b for a, b in zip(hs, bws))
        ao, bo = sigmoid_pwl(asum), tanh_pwl(bsum)
        history.extend(hs)
        aw.extend(aws)
        bw.extend(bws)
        abias.append(ai)
        bbias.append(bi)
        alpha_out.append(ao)
        beta_out.append(bo)
        true_sigmoid_error = max(true_sigmoid_error, abs(ao / 127.0 - 1.0 / (1.0 + __import__("math").exp(-asum / 128.0))))
        true_tanh_error = max(true_tanh_error, abs(bo / 127.0 - __import__("math").tanh(bsum / 128.0)))
    conv_history.append(pack(history, 8))
    conv_aw.append(pack(aw, 4))
    conv_bw.append(pack(bw, 4))
    conv_ab.append(pack(abias, 16))
    conv_bb.append(pack(bbias, 16))
    conv_alpha_golden.append(pack(alpha_out, 8))
    conv_beta_golden.append(pack(beta_out, 8))
write_hex("conv_history.mem", conv_history, 512)
write_hex("conv_alpha_weights.mem", conv_aw, 256)
write_hex("conv_beta_weights.mem", conv_bw, 256)
write_hex("conv_alpha_bias.mem", conv_ab, 256)
write_hex("conv_beta_bias.mem", conv_bb, 256)
write_hex("conv_alpha_golden.mem", conv_alpha_golden, 128)
write_hex("conv_beta_golden.mem", conv_beta_golden, 128)


# RMSNorm: leading-one reciprocal-root LUT, matching the synthesis-safe Y5 RTL.
def rsqrt_lut_q14(value: int) -> int:
    table = [16384,11585,8192,5793,4096,2896,2048,1448,1024,724,512,362,256,181,128,91,64,45,32,23,16,11,8,6,4,3,2,2]
    return table[min(value.bit_length() - 1, len(table) - 1)] if value else table[0]
norm_samples = [((i * 37) % 401) - 200 for i in range(128)]
mean_square = sum(v * v for v in norm_samples) >> 7
scale_q14 = rsqrt_lut_q14(mean_square + 1)
norm_output = [sat((v * scale_q14) >> 14, 8) for v in norm_samples]
write_hex("norm_input.mem", [pack(norm_samples[b * 16:(b + 1) * 16], 24) for b in range(8)], 384)
write_hex("norm_golden.mem", [pack(norm_output[b * 16:(b + 1) * 16], 8) for b in range(8)], 128)


# Integration token: identity projection of constant 64, alpha=beta=64,
# zero initial state, producing S_new=16, q^T S_new=1024, RMSNorm=1,
# and residual skip=3 for a final output of 4 in every lane.
int_x = [64] * 128
int_activ = [pack(int_x[b * 16:(b + 1) * 16], 8) for b in range(8)]
int_weights: list[int] = []
for tile in range(8):
    flat = []
    for r in range(128):
        for c in range(16):
            flat.append(1 if r == tile * 16 + c else 0)
    for beat in range(32):
        int_weights.append(pack(flat[beat * 64:(beat + 1) * 64], 4))
write_hex("integration_activation.mem", int_activ, 128)
write_hex("integration_weights.mem", int_weights, 256)
write_hex("integration_projection.mem", [pack([64] * 16, 24)] * 8, 384)
write_hex("integration_zero_state.mem", [0] * 128, 3072)
write_hex("integration_delta.mem", [pack([32] * 128, 24)], 3072)
write_hex("integration_state_updated.mem", [pack([16] * 128, 24)] * 128, 3072)
write_hex("integration_qout.mem", [pack([1024] * 128, 24)], 3072)
write_hex("integration_norm.mem", [pack([1] * 16, 8)] * 8, 128)
write_hex("integration_final.mem", [pack([4] * 16, 8)] * 8, 128)


# Metadata consumed by humans and CI logs.
(VEC / "metrics.txt").write_text(
    f"norm_mean_square={mean_square}\n"
    f"norm_scale_q14={scale_q14}\n"
    f"conv_max_sigmoid_error={true_sigmoid_error:.6f}\n"
    f"conv_max_tanh_error={true_tanh_error:.6f}\n"
)
print(f"generated vectors in {VEC}")
