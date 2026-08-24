// 16x16 INT4 MAC array, v13 dual-element MACs (2 elements/cycle, 24b out).
// Row r consumes activation lanes a0[r],a1[r]; column c weight lanes
// b0[c],b1[c] -- one outer-product step per element of the pair.
module mac_array_v13 #(
    parameter ROWS = 16,
    parameter COLS = 16
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,
    input wire signed [ROWS*4-1:0] activations0,
    input wire signed [ROWS*4-1:0] activations1,
    input wire signed [COLS*4-1:0] weights0,
    input wire signed [COLS*4-1:0] weights1,
    output wire signed [ROWS*COLS*24-1:0] acc_out
);
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row
            for (c = 0; c < COLS; c = c + 1) begin : col
                int4_mac_v13 mac (
                    .clk(clk), .rst_n(rst_n), .en(en), .clear(clear), .drain(drain),
                    .a0(activations0[r*4 +: 4]),
                    .a1(activations1[r*4 +: 4]),
                    .b0(weights0[c*4 +: 4]),
                    .b1(weights1[c*4 +: 4]),
                    .acc(acc_out[(r*COLS + c)*24 +: 24])
                );
            end
        end
    endgenerate
endmodule
