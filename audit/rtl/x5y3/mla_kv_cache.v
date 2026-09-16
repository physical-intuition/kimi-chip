`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// MLA KV Cache SRAM
//
// Implements the growing KV cache from nano-kpu model.py _mla():
//   self.kv_k[li].append(k)  # k: [n_heads, mla_dk + mla_dr] = [2, 48]
//   self.kv_v[li].append(v)  # v: [n_heads, mla_dv] = [2, 32]
//   K = np.stack(self.kv_k[li])  # [T, H, 48]
//   V = np.stack(self.kv_v[li])  # [T, H, 32]
//
// Unlike KDA's fixed 128×128 state, MLA KV cache GROWS with sequence length.
// Hardware must track write pointer and support softmax over [0:T-1].
//
// Parameters (nano config):
//   MAX_SEQ = 64
//   N_HEADS = 2
//   DK_DR = mla_dk + mla_dr = 48
//   DV = mla_dv = 32
//-----------------------------------------------------------------------------
module mla_kv_cache #(
    parameter MAX_SEQ = 64,
    parameter N_HEADS = 2,
    parameter DK_DR   = 48,   // mla_dk + mla_dr
    parameter DV      = 32    // mla_dv
)(
    input  wire                           clk,
    input  wire                           rst_n,
    
    // Reset cache for new sequence
    input  wire                           cache_reset,
    
    // Append new KV pair (one per token)
    input  wire                           append_valid,
    input  wire [N_HEADS*DK_DR*32-1:0]    k_in,    // [H, dk+dr] flattened FP32
    input  wire [N_HEADS*DV*32-1:0]       v_in,    // [H, dv] flattened FP32
    
    // Current sequence length
    output reg  [6:0]                     seq_len,  // 0 to MAX_SEQ
    
    // Read K for attention: returns K[t, head, :]
    input  wire [5:0]                     k_rd_pos,
    input  wire                           k_rd_head,
    output wire [DK_DR*32-1:0]            k_rd_data,
    
    // Read V for attention: returns V[t, head, :]
    input  wire [5:0]                     v_rd_pos,
    input  wire                           v_rd_head,
    output wire [DV*32-1:0]               v_rd_data
);

    // K cache: MAX_SEQ × N_HEADS × DK_DR × 32-bit
    // For nano: 64 × 2 × 48 × 32 = 196,608 bits = 6144 FP32 values
    reg [31:0] k_cache [0:MAX_SEQ-1][0:N_HEADS-1][0:DK_DR-1];
    
    // V cache: MAX_SEQ × N_HEADS × DV × 32-bit  
    // For nano: 64 × 2 × 32 × 32 = 131,072 bits = 4096 FP32 values
    reg [31:0] v_cache [0:MAX_SEQ-1][0:N_HEADS-1][0:DV-1];
    
    integer t, h, d;
    
    // Append logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq_len <= 7'd0;
        end else if (cache_reset) begin
            seq_len <= 7'd0;
        end else if (append_valid && seq_len < MAX_SEQ) begin
            // Write k_in to k_cache[seq_len]
            for (h = 0; h < N_HEADS; h = h + 1) begin
                for (d = 0; d < DK_DR; d = d + 1) begin
                    k_cache[seq_len][h][d] <= k_in[(h*DK_DR + d)*32 +: 32];
                end
            end
            // Write v_in to v_cache[seq_len]
            for (h = 0; h < N_HEADS; h = h + 1) begin
                for (d = 0; d < DV; d = d + 1) begin
                    v_cache[seq_len][h][d] <= v_in[(h*DV + d)*32 +: 32];
                end
            end
            seq_len <= seq_len + 1;
        end
    end
    
    // K read: combinational for simplicity (could pipeline for timing)
    genvar gd;
    generate
        for (gd = 0; gd < DK_DR; gd = gd + 1) begin : gen_k_rd
            assign k_rd_data[gd*32 +: 32] = k_cache[k_rd_pos][k_rd_head][gd];
        end
        for (gd = 0; gd < DV; gd = gd + 1) begin : gen_v_rd
            assign v_rd_data[gd*32 +: 32] = v_cache[v_rd_pos][v_rd_head][gd];
        end
    endgenerate

endmodule
