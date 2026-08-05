// Ultra-compact 16x16 INT4 MAC Array
// 16-bit accumulators - sufficient for 256 accumulations of INT4*INT4
module mac_array_v2 #(
    parameter ROWS = 16,
    parameter COLS = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    en,
    input  wire                    clear,
    input  wire [ROWS*4-1:0]       act_in,
    input  wire [COLS*4-1:0]       wgt_in,
    output wire [ROWS*COLS*16-1:0] acc_out
);

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row_gen
            for (c = 0; c < COLS; c = c + 1) begin : col_gen
                int4_mac_v2 u_mac (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .en     (en),
                    .clear  (clear),
                    .a      (act_in[r*4 +: 4]),
                    .w      (wgt_in[c*4 +: 4]),
                    .acc    (acc_out[(r*COLS + c)*16 +: 16])
                );
            end
        end
    endgenerate

endmodule
