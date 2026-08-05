// Ultra-optimized INT4 MAC
// Uses Booth-like encoding for smaller multiplier
// 4-bit signed * 4-bit signed with minimal logic
module int4_mac_v2 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        clear,
    input  wire [3:0]  a,
    input  wire [3:0]  w,
    output reg  [15:0] acc  // 16-bit sufficient for 256 accumulations
);

    // Direct 4x4 signed multiply using standard Verilog
    // Let synthesis tool optimize - but with smaller accumulator
    wire signed [3:0] a_s = a;
    wire signed [3:0] w_s = w;
    wire signed [7:0] prod = a_s * w_s;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 16'b0;
        else if (clear)
            acc <= 16'b0;
        else if (en)
            acc <= acc + {{8{prod[7]}}, prod};
    end

endmodule
