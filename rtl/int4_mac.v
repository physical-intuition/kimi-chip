// INT4 Multiply-Accumulate Unit
// 4-bit signed inputs, 32-bit accumulator output
module int4_mac (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        clear,
    input  wire [3:0]  a,      // INT4 activation (-8 to 7)
    input  wire [3:0]  w,      // INT4 weight (-8 to 7)
    output reg  [31:0] acc     // 32-bit accumulator
);

    wire signed [3:0]  a_signed = a;
    wire signed [3:0]  w_signed = w;
    wire signed [7:0]  product  = a_signed * w_signed;
    wire signed [31:0] product_ext = {{24{product[7]}}, product};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 32'b0;
        end else if (clear) begin
            acc <= 32'b0;
        end else if (en) begin
            acc <= acc + product_ext;
        end
    end

endmodule
