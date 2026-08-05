// Optimized INT4 Multiply-Accumulate Unit
// Key optimizations:
// 1. Reduced accumulator from 32b to 20b (INT4*INT4 max = 64, 256 accumulations = 16384, fits in 15b signed)
// 2. Single-cycle multiply-accumulate (no pipeline needed at target freq)
module int4_mac_opt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        clear,
    input  wire [3:0]  a,      // INT4 activation (-8 to 7)
    input  wire [3:0]  w,      // INT4 weight (-8 to 7)
    output reg  [19:0] acc     // 20-bit accumulator (sufficient for 1024 accumulations)
);

    wire signed [3:0]  a_s = a;
    wire signed [3:0]  w_s = w;
    wire signed [7:0]  prod = a_s * w_s;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 20'b0;
        else if (clear)
            acc <= 20'b0;
        else if (en)
            acc <= acc + {{12{prod[7]}}, prod};
    end

endmodule
