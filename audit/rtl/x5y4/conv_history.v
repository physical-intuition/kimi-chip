`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Conv History Shift Register Bank - X2Y3 Version
// 
// X2Y3 Fix: Pre-register per-stream enables AND separate arrays per stream
// Each stream has its own registered enable and array, eliminating
// the stream_sel decode from the critical path entirely
//-----------------------------------------------------------------------------
module conv_history #(
    parameter STREAMS = 3,
    parameter KERNEL  = 4,
    parameter WIDTH   = 64,
    parameter DEPTH   = KERNEL - 1
)(
    input  wire                           clk,
    input  wire                           rst_n,
    
    input  wire [1:0]                     stream_sel,
    input  wire                           push_valid,
    input  wire [WIDTH*32-1:0]            push_data,
    
    input  wire [1:0]                     read_stream,
    output wire [KERNEL*WIDTH*32-1:0]     window_data
);

    //-------------------------------------------------------------------------
    // X2Y3: Pre-decode AND register per-stream enables
    //-------------------------------------------------------------------------
    reg stream_en_0_q, stream_en_1_q, stream_en_2_q;
    reg [WIDTH*32-1:0] push_data_q;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_en_0_q <= 1'b0;
            stream_en_1_q <= 1'b0;
            stream_en_2_q <= 1'b0;
            push_data_q   <= {(WIDTH*32){1'b0}};
        end else begin
            stream_en_0_q <= push_valid && (stream_sel == 2'd0);
            stream_en_1_q <= push_valid && (stream_sel == 2'd1);
            stream_en_2_q <= push_valid && (stream_sel == 2'd2);
            push_data_q   <= push_data;
        end
    end
    
    //-------------------------------------------------------------------------
    // Storage - separate arrays per stream
    //-------------------------------------------------------------------------
    reg [31:0] history_0 [0:DEPTH-1][0:WIDTH-1];
    reg [31:0] history_1 [0:DEPTH-1][0:WIDTH-1];
    reg [31:0] history_2 [0:DEPTH-1][0:WIDTH-1];
    
    reg [31:0] current_0 [0:WIDTH-1];
    reg [31:0] current_1 [0:WIDTH-1];
    reg [31:0] current_2 [0:WIDTH-1];
    
    // Stream 0 update - block-local loop variables
    always @(posedge clk or negedge rst_n) begin : stream0_update
        integer d0, w0;
        if (!rst_n) begin
            for (d0 = 0; d0 < DEPTH; d0 = d0 + 1)
                for (w0 = 0; w0 < WIDTH; w0 = w0 + 1)
                    history_0[d0][w0] <= 32'b0;
            for (w0 = 0; w0 < WIDTH; w0 = w0 + 1)
                current_0[w0] <= 32'b0;
        end else if (stream_en_0_q) begin
            for (d0 = 0; d0 < DEPTH - 1; d0 = d0 + 1)
                for (w0 = 0; w0 < WIDTH; w0 = w0 + 1)
                    history_0[d0][w0] <= history_0[d0+1][w0];
            for (w0 = 0; w0 < WIDTH; w0 = w0 + 1)
                history_0[DEPTH-1][w0] <= current_0[w0];
            for (w0 = 0; w0 < WIDTH; w0 = w0 + 1)
                current_0[w0] <= push_data_q[w0*32 +: 32];
        end
    end
    
    // Stream 1 update - block-local loop variables
    always @(posedge clk or negedge rst_n) begin : stream1_update
        integer d1, w1;
        if (!rst_n) begin
            for (d1 = 0; d1 < DEPTH; d1 = d1 + 1)
                for (w1 = 0; w1 < WIDTH; w1 = w1 + 1)
                    history_1[d1][w1] <= 32'b0;
            for (w1 = 0; w1 < WIDTH; w1 = w1 + 1)
                current_1[w1] <= 32'b0;
        end else if (stream_en_1_q) begin
            for (d1 = 0; d1 < DEPTH - 1; d1 = d1 + 1)
                for (w1 = 0; w1 < WIDTH; w1 = w1 + 1)
                    history_1[d1][w1] <= history_1[d1+1][w1];
            for (w1 = 0; w1 < WIDTH; w1 = w1 + 1)
                history_1[DEPTH-1][w1] <= current_1[w1];
            for (w1 = 0; w1 < WIDTH; w1 = w1 + 1)
                current_1[w1] <= push_data_q[w1*32 +: 32];
        end
    end
    
    // Stream 2 update - block-local loop variables
    always @(posedge clk or negedge rst_n) begin : stream2_update
        integer d2, w2;
        if (!rst_n) begin
            for (d2 = 0; d2 < DEPTH; d2 = d2 + 1)
                for (w2 = 0; w2 < WIDTH; w2 = w2 + 1)
                    history_2[d2][w2] <= 32'b0;
            for (w2 = 0; w2 < WIDTH; w2 = w2 + 1)
                current_2[w2] <= 32'b0;
        end else if (stream_en_2_q) begin
            for (d2 = 0; d2 < DEPTH - 1; d2 = d2 + 1)
                for (w2 = 0; w2 < WIDTH; w2 = w2 + 1)
                    history_2[d2][w2] <= history_2[d2+1][w2];
            for (w2 = 0; w2 < WIDTH; w2 = w2 + 1)
                history_2[DEPTH-1][w2] <= current_2[w2];
            for (w2 = 0; w2 < WIDTH; w2 = w2 + 1)
                current_2[w2] <= push_data_q[w2*32 +: 32];
        end
    end
    
    //-------------------------------------------------------------------------
    // Read mux
    //-------------------------------------------------------------------------
    genvar gi, gw;
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : gen_hist_out
            for (gw = 0; gw < WIDTH; gw = gw + 1) begin : gen_hist_word
                assign window_data[(gi*WIDTH + gw)*32 +: 32] = 
                    (read_stream == 2'd0) ? history_0[gi][gw] :
                    (read_stream == 2'd1) ? history_1[gi][gw] :
                                            history_2[gi][gw];
            end
        end
        for (gw = 0; gw < WIDTH; gw = gw + 1) begin : gen_curr_out
            assign window_data[(DEPTH*WIDTH + gw)*32 +: 32] = 
                (read_stream == 2'd0) ? current_0[gw] :
                (read_stream == 2'd1) ? current_1[gw] :
                                        current_2[gw];
        end
    endgenerate

endmodule
