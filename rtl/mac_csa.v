// Carry-Save Accumulator MAC
// Delays final carry propagation until output read
// Reduces critical path in accumulator
module mac_csa (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        clear,
    input  wire [3:0]  a,
    input  wire [3:0]  w,
    output wire [15:0] acc_out  // Final sum computed on output
);

    wire signed [3:0] a_s = a;
    wire signed [3:0] w_s = w;
    wire signed [7:0] prod = a_s * w_s;
    wire [15:0] prod_ext = {{8{prod[7]}}, prod};
    
    // Carry-save representation: sum + carry
    reg [15:0] sum_r, carry_r;
    
    // 3:2 compressor (full adder per bit)
    wire [15:0] new_sum = sum_r ^ carry_r ^ prod_ext;
    wire [15:0] new_carry = ((sum_r & carry_r) | (sum_r & prod_ext) | (carry_r & prod_ext)) << 1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_r <= 16'b0;
            carry_r <= 16'b0;
        end else if (clear) begin
            sum_r <= 16'b0;
            carry_r <= 16'b0;
        end else if (en) begin
            sum_r <= new_sum;
            carry_r <= new_carry;
        end
    end
    
    // Final addition only on output
    assign acc_out = sum_r + carry_r;

endmodule
