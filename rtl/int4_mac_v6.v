// Pipelined + 12-bit accumulator
module int4_mac_v6 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire [3:0] a,
    input wire [3:0] w,
    output reg [11:0] acc
);
    // Pipeline stage 1
    reg [7:0] prod_r;
    reg en_r, clear_r;
    
    wire signed [3:0] a_s = a;
    wire signed [3:0] w_s = w;
    wire signed [7:0] prod = a_s * w_s;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_r <= 0; en_r <= 0; clear_r <= 0;
        end else begin
            prod_r <= prod; en_r <= en; clear_r <= clear;
        end
    end
    
    // Stage 2: accumulate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc <= 0;
        else if (clear_r) acc <= 0;
        else if (en_r) acc <= acc + {{4{prod_r[7]}}, prod_r};
    end
endmodule
