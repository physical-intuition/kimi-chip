`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// KDA State SRAM
//
// Implements the fixed recurrent state from nano-kpu model.py _kda():
//   self.kda_state[i] = np.zeros((c.kda_heads, c.kda_dim, c.kda_dim), dtype=F32)
//   # Shape: [2, 32, 32] for nano config
//
//   S = alpha[hd][:, None] * self.kda_state[li][hd]  # decay: element-wise scale rows
//   u = vh - kh @ S                                   # delta = v - k·S
//   S = S + np.outer(kh * beta[hd], u)               # rank-1 update
//   self.kda_state[li][hd] = S
//
// Key insight: KDA state is FIXED SIZE (128×128 per head for production,
// 32×32 per head for nano). Unlike MLA KV cache, it doesn't grow with T.
// But it requires READ-MODIFY-WRITE each token:
//   1. Read entire S matrix
//   2. Compute α·S + β·k·uᵀ
//   3. Write entire S matrix back
//
// Parameters (nano config):
//   KDA_HEADS = 2
//   KDA_DIM = 32
//   State shape = [2, 32, 32] = 2048 FP32 values = 8 KiB
//-----------------------------------------------------------------------------
module kda_state_sram #(
    parameter KDA_HEADS = 2,
    parameter KDA_DIM   = 32
)(
    input  wire                              clk,
    input  wire                              rst_n,
    
    // Reset state for new sequence
    input  wire                              state_reset,
    
    // Read entire state matrix for one head
    input  wire                              rd_en,
    input  wire [$clog2(KDA_HEADS)-1:0]      rd_head,
    output wire [KDA_DIM*KDA_DIM*32-1:0]     rd_data,  // [32, 32] flattened
    
    // Write entire state matrix for one head
    input  wire                              wr_en,
    input  wire [$clog2(KDA_HEADS)-1:0]      wr_head,
    input  wire [KDA_DIM*KDA_DIM*32-1:0]     wr_data   // [32, 32] flattened
);

    // State storage: KDA_HEADS × KDA_DIM × KDA_DIM × 32-bit
    // For nano: 2 × 32 × 32 × 32 = 65,536 bits = 2048 FP32 values = 8 KiB
    reg [31:0] state [0:KDA_HEADS-1][0:KDA_DIM-1][0:KDA_DIM-1];
    
    integer h, i, j;
    
    // Write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (h = 0; h < KDA_HEADS; h = h + 1) begin
                for (i = 0; i < KDA_DIM; i = i + 1) begin
                    for (j = 0; j < KDA_DIM; j = j + 1) begin
                        state[h][i][j] <= 32'b0;
                    end
                end
            end
        end else if (state_reset) begin
            for (h = 0; h < KDA_HEADS; h = h + 1) begin
                for (i = 0; i < KDA_DIM; i = i + 1) begin
                    for (j = 0; j < KDA_DIM; j = j + 1) begin
                        state[h][i][j] <= 32'b0;
                    end
                end
            end
        end else if (wr_en) begin
            for (i = 0; i < KDA_DIM; i = i + 1) begin
                for (j = 0; j < KDA_DIM; j = j + 1) begin
                    state[wr_head][i][j] <= wr_data[(i*KDA_DIM + j)*32 +: 32];
                end
            end
        end
    end
    
    // Read logic: output entire matrix for selected head
    genvar gi, gj;
    generate
        for (gi = 0; gi < KDA_DIM; gi = gi + 1) begin : gen_rd_row
            for (gj = 0; gj < KDA_DIM; gj = gj + 1) begin : gen_rd_col
                assign rd_data[(gi*KDA_DIM + gj)*32 +: 32] = 
                    state[rd_head][gi][gj];
            end
        end
    endgenerate

endmodule
