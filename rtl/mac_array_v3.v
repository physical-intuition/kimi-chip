// Weight-stationary MAC Array v3
// Key insight: each column shares the same weight, each row shares the same activation
// So we can compute products once and broadcast to accumulators
module mac_array_v3 #(
    parameter ROWS = 16,
    parameter COLS = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    en,
    input  wire                    clear,
    input  wire [ROWS*4-1:0]       act_in,  // 16 activations
    input  wire [COLS*4-1:0]       wgt_in,  // 16 weights  
    output wire [ROWS*COLS*16-1:0] acc_out
);

    // Pre-compute all 16x16 products in combinational logic
    // Then accumulate - this shares the multiply cost
    wire signed [7:0] products [0:ROWS-1][0:COLS-1];
    
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : prod_row
            wire signed [3:0] act_s = act_in[r*4 +: 4];
            for (c = 0; c < COLS; c = c + 1) begin : prod_col
                wire signed [3:0] wgt_s = wgt_in[c*4 +: 4];
                assign products[r][c] = act_s * wgt_s;
            end
        end
    endgenerate
    
    // Accumulators only - no per-MAC multiply logic
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : acc_row
            for (c = 0; c < COLS; c = c + 1) begin : acc_col
                reg [15:0] acc;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n)
                        acc <= 16'b0;
                    else if (clear)
                        acc <= 16'b0;
                    else if (en)
                        acc <= acc + {{8{products[r][c][7]}}, products[r][c]};
                end
                assign acc_out[(r*COLS + c)*16 +: 16] = acc;
            end
        end
    endgenerate

endmodule
