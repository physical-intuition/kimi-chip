`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Conv History Shift Register Bank - X2Y2 Version (Fixed)
// 
// X2Y1 Fix: Register stream_sel and push_valid before fanout
// X2Y2 Fix: One-hot pre-decode of stream_sel to reduce decode logic depth
//           Use generate to create separate always blocks per stream
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
    // X2Y1: Pipeline registers for write controls
    //-------------------------------------------------------------------------
    reg [1:0]            stream_sel_q;
    reg                  push_valid_q;
    reg [WIDTH*32-1:0]   push_data_q;
    
    //-------------------------------------------------------------------------
    // X2Y2 FIX: One-hot decode of stream select
    //-------------------------------------------------------------------------
    wire [STREAMS-1:0] stream_en;
    
    assign stream_en[0] = push_valid_q && (stream_sel_q == 2'd0);
    assign stream_en[1] = push_valid_q && (stream_sel_q == 2'd1);
    assign stream_en[2] = push_valid_q && (stream_sel_q == 2'd2);
    
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
    // Storage - use generate to create independent always blocks per stream
    //-------------------------------------------------------------------------
    reg [31:0] history [0:STREAMS-1][0:DEPTH-1][0:WIDTH-1];
    reg [31:0] current [0:STREAMS-1][0:WIDTH-1];
    
    // Generate separate always blocks for each stream
    genvar gs;
    generate
        for (gs = 0; gs < STREAMS; gs = gs + 1) begin : gen_stream
            integer gd, gw;  // Each generate block has its own integers
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (gd = 0; gd < DEPTH; gd = gd + 1) begin
                        for (gw = 0; gw < WIDTH; gw = gw + 1) begin
                            history[gs][gd][gw] <= 32'b0;
                        end
                    end
                    for (gw = 0; gw < WIDTH; gw = gw + 1) begin
                        current[gs][gw] <= 32'b0;
                    end
                end else if (stream_en[gs]) begin
                    // Shift history
                    for (gd = 0; gd < DEPTH - 1; gd = gd + 1) begin
                        for (gw = 0; gw < WIDTH; gw = gw + 1) begin
                            history[gs][gd][gw] <= history[gs][gd+1][gw];
                        end
                    end
                    // Move current to history tail
                    for (gw = 0; gw < WIDTH; gw = gw + 1) begin
                        history[gs][DEPTH-1][gw] <= current[gs][gw];
                    end
                    // Load new current
                    for (gw = 0; gw < WIDTH; gw = gw + 1) begin
                        current[gs][gw] <= push_data_q[gw*32 +: 32];
                    end
                end
            end
        end
    endgenerate
    
    // Read path unchanged
    genvar gi, gw2;
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : gen_hist_out
            for (gw2 = 0; gw2 < WIDTH; gw2 = gw2 + 1) begin : gen_hist_word
                assign window_data[(gi*WIDTH + gw2)*32 +: 32] = 
                    history[read_stream][gi][gw2];
            end
        end
        for (gw2 = 0; gw2 < WIDTH; gw2 = gw2 + 1) begin : gen_curr_out
            assign window_data[(DEPTH*WIDTH + gw2)*32 +: 32] = 
                current[read_stream][gw2];
        end
    endgenerate

endmodule
