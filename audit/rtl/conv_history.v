`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Conv History Shift Register Bank
// 
// Implements the causal depthwise conv history from nano-kpu model.py _conv():
//   hist = self.conv_hist[li][stream]                 # [K-1, D]
//   win = np.concatenate([hist, x[None, :]], axis=0)  # [K, D]
//   y = silu((win.T * w).sum(axis=-1))
//   self.conv_hist[li][stream] = np.concatenate([hist[1:], x[None, :]], axis=0)
//
// Parameters (nano config):
//   STREAMS = 3 (q, k, v)
//   KERNEL = 4
//   WIDTH = kda_heads * kda_dim = 64
//   History depth = KERNEL - 1 = 3
//-----------------------------------------------------------------------------
module conv_history #(
    parameter STREAMS = 3,
    parameter KERNEL  = 4,
    parameter WIDTH   = 64,
    parameter DEPTH   = KERNEL - 1  // 3 for kernel=4
)(
    input  wire                           clk,
    input  wire                           rst_n,
    
    // Push new value into a stream's history
    input  wire [1:0]                     stream_sel,    // 0=q, 1=k, 2=v
    input  wire                           push_valid,
    input  wire [WIDTH*32-1:0]            push_data,     // new x[t], FP32 packed
    
    // Read full window [K, WIDTH] for conv computation
    input  wire [1:0]                     read_stream,
    output wire [KERNEL*WIDTH*32-1:0]     window_data    // [K, WIDTH] flattened
);

    // Storage: STREAMS × DEPTH × WIDTH × 32-bit
    // For nano: 3 × 3 × 64 × 32 = 18,432 bits = 576 FP32 values
    reg [31:0] history [0:STREAMS-1][0:DEPTH-1][0:WIDTH-1];
    
    // Current input register (the K-th element of window)
    reg [31:0] current [0:STREAMS-1][0:WIDTH-1];
    
    integer s, d, w;
    
    // Shift register: push_data becomes newest history, oldest drops off
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < STREAMS; s = s + 1) begin
                for (d = 0; d < DEPTH; d = d + 1) begin
                    for (w = 0; w < WIDTH; w = w + 1) begin
                        history[s][d][w] <= 32'b0;
                    end
                end
                for (w = 0; w < WIDTH; w = w + 1) begin
                    current[s][w] <= 32'b0;
                end
            end
        end else if (push_valid) begin
            // Shift history: [1:] becomes [:-1], new value becomes [-1]
            for (d = 0; d < DEPTH - 1; d = d + 1) begin
                for (w = 0; w < WIDTH; w = w + 1) begin
                    history[stream_sel][d][w] <= history[stream_sel][d+1][w];
                end
            end
            // Previous current becomes newest history element
            for (w = 0; w < WIDTH; w = w + 1) begin
                history[stream_sel][DEPTH-1][w] <= current[stream_sel][w];
            end
            // New input becomes current
            for (w = 0; w < WIDTH; w = w + 1) begin
                current[stream_sel][w] <= push_data[w*32 +: 32];
            end
        end
    end
    
    // Output: concatenate history[0:DEPTH-1] + current to form [KERNEL, WIDTH]
    // window_data layout: oldest first, newest last
    genvar gi, gw;
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : gen_hist_out
            for (gw = 0; gw < WIDTH; gw = gw + 1) begin : gen_hist_word
                assign window_data[(gi*WIDTH + gw)*32 +: 32] = 
                    history[read_stream][gi][gw];
            end
        end
        // Current (newest) is the last row of window
        for (gw = 0; gw < WIDTH; gw = gw + 1) begin : gen_curr_out
            assign window_data[(DEPTH*WIDTH + gw)*32 +: 32] = 
                current[read_stream][gw];
        end
    endgenerate

endmodule
