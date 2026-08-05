// 16x16 INT4 MAC Array (256 parallel MACs)
// Systolic-style architecture for matrix multiplication
module mac_array #(
    parameter ROWS = 16,
    parameter COLS = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire                     clear,
    input  wire [ROWS*4-1:0]        act_in,    // 16 INT4 activations
    input  wire [COLS*4-1:0]        wgt_in,    // 16 INT4 weights
    output wire [ROWS*COLS*32-1:0]  acc_out    // 256 x 32-bit accumulators
);

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row_gen
            for (c = 0; c < COLS; c = c + 1) begin : col_gen
                wire [3:0] act = act_in[r*4 +: 4];
                wire [3:0] wgt = wgt_in[c*4 +: 4];
                wire [31:0] acc;
                
                int4_mac u_mac (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .en     (en),
                    .clear  (clear),
                    .a      (act),
                    .w      (wgt),
                    .acc    (acc)
                );
                
                assign acc_out[(r*COLS + c)*32 +: 32] = acc;
            end
        end
    endgenerate

endmodule
