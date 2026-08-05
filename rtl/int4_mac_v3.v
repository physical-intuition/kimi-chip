// INT4 MAC with 2-stage pipeline for higher frequency
// Stage 1: multiply, Stage 2: accumulate
module int4_mac_v3 #(
    parameter ACC_WIDTH = 16
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire signed [3:0] a,
    input wire signed [3:0] b,
    output reg signed [ACC_WIDTH-1:0] acc
);
    // Pipeline registers
    reg signed [7:0] prod_r;      // Stage 1 output
    reg en_r, clear_r;            // Control pipeline
    
    // Stage 1: Multiply
    wire signed [7:0] prod = a * b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_r <= 0;
            en_r <= 0;
            clear_r <= 0;
        end else begin
            prod_r <= prod;
            en_r <= en;
            clear_r <= clear;
        end
    end
    
    // Stage 2: Accumulate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 0;
        else if (clear_r)
            acc <= 0;
        else if (en_r)
            acc <= acc + {{(ACC_WIDTH-8){prod_r[7]}}, prod_r};
    end
endmodule
