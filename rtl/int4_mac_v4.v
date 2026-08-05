// INT4 MAC with 12-bit accumulator
// Sufficient for 64 accumulations (max 64*64 = 4096, fits in 12 bits signed)
module int4_mac_v4 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire signed [3:0] a,
    input wire signed [3:0] b,
    output reg signed [11:0] acc
);
    wire signed [7:0] prod = a * b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 0;
        else if (clear)
            acc <= 0;
        else if (en)
            acc <= acc + {{4{prod[7]}}, prod};
    end
endmodule
