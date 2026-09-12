`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Conv History Shift Register Bank - X2Y1 Version
// 
// X2 Fix: Register stream_sel and push_valid before fanout to history array
// This adds 1 cycle latency but reduces critical path timing pressure
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
    // X2Y1 FIX: Pipeline registers for write controls before fanout
    //-------------------------------------------------------------------------
    reg [1:0]            stream_sel_q;
    reg                  push_valid_q;
    reg [WIDTH*32-1:0]   push_data_q;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_sel_q <= 2'b0;
            push_valid_q <= 1'b0;
            push_data_q  <= {(WIDTH*32){1'b0}};
        end else begin
            stream_sel_q <= stream_sel;
            push_valid_q <= push_valid;
            push_data_q  <= push_data;
        end
    end
    
    //-------------------------------------------------------------------------
    // Storage (uses registered controls)
    //-------------------------------------------------------------------------
    reg [31:0] history [0:STREAMS-1][0:DEPTH-1][0:WIDTH-1];
    reg [31:0] current [0:STREAMS-1][0:WIDTH-1];
    
    integer s, d, w;
    
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
        end else if (push_valid_q) begin  // Use registered signal
            for (d = 0; d < DEPTH - 1; d = d + 1) begin
                for (w = 0; w < WIDTH; w = w + 1) begin
                    history[stream_sel_q][d][w] <= history[stream_sel_q][d+1][w];
                end
            end
            for (w = 0; w < WIDTH; w = w + 1) begin
                history[stream_sel_q][DEPTH-1][w] <= current[stream_sel_q][w];
            end
            for (w = 0; w < WIDTH; w = w + 1) begin
                current[stream_sel_q][w] <= push_data_q[w*32 +: 32];
            end
        end
    end
    
    // Read path unchanged
    genvar gi, gw;
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : gen_hist_out
            for (gw = 0; gw < WIDTH; gw = gw + 1) begin : gen_hist_word
                assign window_data[(gi*WIDTH + gw)*32 +: 32] = 
                    history[read_stream][gi][gw];
            end
        end
        for (gw = 0; gw < WIDTH; gw = gw + 1) begin : gen_curr_out
            assign window_data[(DEPTH*WIDTH + gw)*32 +: 32] = 
                current[read_stream][gw];
        end
    endgenerate

endmodule
