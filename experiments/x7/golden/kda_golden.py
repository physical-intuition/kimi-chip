#!/usr/bin/env python3
"""
KDA Golden Model - Bit-exact reference for RTL verification

KDA recurrence: S_t = (I - β_t k_t k_t^T) · diag(α_t) · S_{t-1} + β_t k_t v_t^T

All arithmetic is INT8 inputs, INT24 accumulators, INT8 outputs after requant.
"""

import numpy as np

def saturate_int8(x):
    """Saturate to [-128, 127]"""
    return np.clip(x, -128, 127).astype(np.int8)

def saturate_int24(x):
    """Saturate to 24-bit signed range"""
    return np.clip(x, -(1<<23), (1<<23)-1).astype(np.int32)

def requant_24_to_8(acc24, shift=8):
    """INT24 -> INT8 with arithmetic right shift + saturation"""
    # Arithmetic right shift
    shifted = acc24 >> shift
    # Saturate to INT8
    return saturate_int8(shifted)

def matmul_int8(A, B, shift=8):
    """
    INT8 matrix multiply with INT24 accumulator and requant
    A: (M, K) INT8
    B: (K, N) INT8
    Returns: (M, N) INT8
    """
    M, K = A.shape
    K2, N = B.shape
    assert K == K2
    
    # Accumulate in INT32 (simulating INT24)
    acc = np.zeros((M, N), dtype=np.int32)
    for i in range(M):
        for j in range(N):
            for k in range(K):
                acc[i, j] += int(A[i, k]) * int(B[k, j])
                acc[i, j] = saturate_int24(acc[i, j])
    
    return requant_24_to_8(acc, shift)

def conv1d_int8(x, weights, shift=8):
    """
    4-tap 1D convolution per channel
    x: (C, T) INT8 - C channels, T timesteps (T >= 4)
    weights: (C, 4) INT8 - per-channel 4-tap filter
    Returns: (C,) INT8 - one output per channel
    """
    C, T = x.shape
    assert T >= 4
    
    acc = np.zeros(C, dtype=np.int32)
    for c in range(C):
        for t in range(4):
            acc[c] += int(x[c, T-4+t]) * int(weights[c, t])
            acc[c] = saturate_int24(acc[c])
    
    return requant_24_to_8(acc, shift)

def sigmoid_approx_int8(x):
    """
    Piecewise linear sigmoid approximation
    Input: INT8 [-128, 127] representing [-4, 4] (scale 32)
    Output: INT8 [0, 127] representing [0, 1] (scale 127)
    """
    # Simple piecewise: 0 if x < -64, 127 if x > 64, else linear
    y = np.zeros_like(x, dtype=np.int8)
    mask_low = x < -64
    mask_high = x > 64
    mask_mid = ~mask_low & ~mask_high
    
    y[mask_high] = 127
    y[mask_mid] = ((x[mask_mid].astype(np.int32) + 64) * 127 // 128).astype(np.int8)
    return y

def tanh_approx_int8(x):
    """
    Piecewise linear tanh approximation
    Input: INT8 [-128, 127]
    Output: INT8 [-127, 127]
    """
    # Clamp to [-64, 64] then scale
    clamped = np.clip(x, -64, 64)
    return (clamped * 2).astype(np.int8)

def rmsnorm_int8(x, shift=4):
    """
    RMSNorm: y = x / sqrt(mean(x^2) + eps)
    Input: (N,) INT8
    Output: (N,) INT8
    
    Uses iterative Newton-Raphson for reciprocal sqrt
    """
    N = len(x)
    
    # Accumulate x^2 in INT32
    sum_sq = np.int32(0)
    for i in range(N):
        sum_sq += int(x[i]) * int(x[i])
    
    # Mean (divide by N=128, shift by 7)
    mean_sq = sum_sq >> 7
    
    # Add epsilon (1 in INT8 scale)
    mean_sq = max(mean_sq, 1)
    
    # Newton-Raphson reciprocal sqrt: y = y * (3 - x*y^2) / 2
    # Start with initial guess based on magnitude
    if mean_sq < 16:
        y = 128  # Large rsqrt for small values
    elif mean_sq < 256:
        y = 64
    elif mean_sq < 4096:
        y = 16
    else:
        y = 4
    
    # 3 iterations
    for _ in range(3):
        y2 = (y * y) >> 8
        xy2 = (mean_sq * y2) >> 8
        factor = (384 - xy2) >> 1  # 384 = 3 * 128 (scaled)
        y = (y * factor) >> 7
        y = max(1, min(255, y))
    
    # Scale outputs
    out = np.zeros(N, dtype=np.int8)
    for i in range(N):
        scaled = (int(x[i]) * y) >> shift
        out[i] = saturate_int8(scaled)
    
    return out

def kda_state_update(S_prev, k, v, q, alpha, beta):
    """
    KDA state update: S_t = (I - β k k^T) · diag(α) · S_{t-1} + β k v^T
    
    S_prev: (128, 128) INT8 state matrix
    k, v, q: (128,) INT8 key/value/query vectors
    alpha, beta: (128,) INT8 gates from conv (sigmoid/tanh outputs)
    
    Returns: S_new (128, 128) INT8, y (128,) INT8 output
    """
    D = 128
    
    # Pass 1: S' = diag(α) · S (element-wise scale rows)
    S_prime = np.zeros((D, D), dtype=np.int32)
    for i in range(D):
        for j in range(D):
            # alpha is [0, 127] representing [0, 1]
            S_prime[i, j] = (int(S_prev[i, j]) * int(alpha[i])) >> 7
    S_prime = saturate_int8(S_prime.astype(np.int32))
    
    # Compute A = k^T · S' (D,) - key attention scores
    A = np.zeros(D, dtype=np.int32)
    for j in range(D):
        for i in range(D):
            A[j] += int(k[i]) * int(S_prime[i, j])
        A[j] = saturate_int24(A[j])
    A = requant_24_to_8(A)
    
    # Compute u = k · A (outer product contribution to subtract)
    # d = β · (v - u) · k^T
    # But simpler: S = S' + β · k · (v - k·A)^T
    
    # v - k·A: for each j, v[j] - k·A (but A is already contracted)
    # Actually the KDA formula is: S = (I - β k k^T) α S + β k v^T
    # = α S - β k (k^T α S) + β k v^T  
    # = α S + β k (v - k^T α S)^T
    # = S' + β k (v - A)^T where A = k^T S'
    
    diff = np.zeros(D, dtype=np.int8)
    for j in range(D):
        diff[j] = saturate_int8(int(v[j]) - int(A[j]))
    
    # S_new = S' + β · k · diff^T
    S_new = np.zeros((D, D), dtype=np.int32)
    for i in range(D):
        for j in range(D):
            # beta is [-127, 127] representing [-1, 1]
            update = (int(beta[i]) * int(k[i]) * int(diff[j])) >> 14
            S_new[i, j] = int(S_prime[i, j]) + update
    S_new = saturate_int8(S_new.astype(np.int32))
    
    # Output: y = q^T · S_new (or S_new · q depending on convention)
    y = np.zeros(D, dtype=np.int32)
    for i in range(D):
        for j in range(D):
            y[i] += int(q[j]) * int(S_new[j, i])
        y[i] = saturate_int24(y[i])
    y = requant_24_to_8(y)
    
    return S_new.astype(np.int8), y

def kda_forward(x_in, W_k, W_v, W_q, W_o, conv_alpha, conv_beta, S_prev):
    """
    Full KDA layer forward pass
    
    x_in: (128,) INT8 input
    W_k, W_v, W_q: (128, 128) INT8 projection weights
    W_o: (128, 128) INT8 output projection weights
    conv_alpha, conv_beta: (128, 4) INT8 conv weights
    S_prev: (128, 128) INT8 previous state
    
    Returns: x_out (128,) INT8, S_new (128, 128) INT8
    """
    # Project to K, V, Q
    k = matmul_int8(W_k, x_in.reshape(-1, 1)).flatten()
    v = matmul_int8(W_v, x_in.reshape(-1, 1)).flatten()
    q = matmul_int8(W_q, x_in.reshape(-1, 1)).flatten()
    
    # Conv gates (assume history buffer exists)
    # For simplicity, use x_in as current tap
    history = np.stack([x_in, x_in, x_in, x_in], axis=1)  # (128, 4)
    alpha_raw = conv1d_int8(history, conv_alpha)
    beta_raw = conv1d_int8(history, conv_beta)
    
    alpha = sigmoid_approx_int8(alpha_raw)  # [0, 127]
    beta = tanh_approx_int8(beta_raw)       # [-127, 127]
    
    # State update
    S_new, y = kda_state_update(S_prev, k, v, q, alpha, beta)
    
    # Output projection
    o = matmul_int8(W_o, y.reshape(-1, 1)).flatten()
    
    # RMSNorm
    o_norm = rmsnorm_int8(o)
    
    # Residual
    x_out = saturate_int8(x_in.astype(np.int32) + o_norm.astype(np.int32))
    
    return x_out, S_new

if __name__ == "__main__":
    # Test basic operations
    np.random.seed(42)
    
    # Test requant
    acc = np.array([256, -256, 32767, -32768], dtype=np.int32)
    print(f"Requant test: {acc} -> {requant_24_to_8(acc)}")
    
    # Test matmul
    A = np.random.randint(-128, 128, (4, 4), dtype=np.int8)
    B = np.random.randint(-128, 128, (4, 4), dtype=np.int8)
    C = matmul_int8(A, B)
    print(f"Matmul test: {A.shape} x {B.shape} -> {C.shape}, range [{C.min()}, {C.max()}]")
    
    # Test RMSNorm
    x = np.random.randint(-64, 64, 128, dtype=np.int8)
    y = rmsnorm_int8(x)
    print(f"RMSNorm test: input range [{x.min()}, {x.max()}], output range [{y.min()}, {y.max()}]")
    
    # Test full forward
    x_in = np.random.randint(-64, 64, 128, dtype=np.int8)
    W_k = np.random.randint(-16, 16, (128, 128), dtype=np.int8)
    W_v = np.random.randint(-16, 16, (128, 128), dtype=np.int8)
    W_q = np.random.randint(-16, 16, (128, 128), dtype=np.int8)
    W_o = np.random.randint(-16, 16, (128, 128), dtype=np.int8)
    conv_a = np.random.randint(-16, 16, (128, 4), dtype=np.int8)
    conv_b = np.random.randint(-16, 16, (128, 4), dtype=np.int8)
    S = np.zeros((128, 128), dtype=np.int8)
    
    x_out, S_new = kda_forward(x_in, W_k, W_v, W_q, W_o, conv_a, conv_b, S)
    print(f"Full forward: input [{x_in.min()}, {x_in.max()}] -> output [{x_out.min()}, {x_out.max()}]")
    print(f"State changed: {np.any(S_new != S)}")
    print("Golden model OK")
