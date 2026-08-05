// Minimal MAC - 8-bit accumulator for K<=4
module int4_mac_v8 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire [3:0] a,
    input wire [3:0] w,
    output reg [7:0] acc
);
    wire signed [3:0] a_s = a;
    wire signed [3:0] w_s = w;
    wire signed [7:0] prod = a_s * w_s;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc <= 0;
        else if (clear) acc <= 0;
        else if (en) acc <= acc + prod;
    end
endmodule
