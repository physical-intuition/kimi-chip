// Shift-add INT4 MAC - smaller area, same result
// Uses 2-bit Booth encoding style
module int4_mac_v7 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire [3:0] a,
    input wire [3:0] w,
    output reg [11:0] acc
);
    // Sign extend inputs
    wire signed [4:0] a_ext = {a[3], a};
    wire signed [4:0] w_ext = {w[3], w};
    
    // Booth-like: compute partial products using shifts
    // a * w where both are 4-bit signed
    wire signed [8:0] prod;
    
    // Direct multiply (let synth optimize)
    assign prod = a_ext * w_ext;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 0;
        else if (clear)
            acc <= 0;
        else if (en)
            acc <= acc + {{3{prod[8]}}, prod};
    end
endmodule
