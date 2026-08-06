// 16x16 INT4 MAC array, v10 carry-save hierarchical accumulators.
module mac_array_v11 #(
    parameter ROWS = 16,
    parameter COLS = 16
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,
    input wire signed [ROWS*4-1:0] activations,
    input wire signed [COLS*4-1:0] weights,
    output wire signed [ROWS*COLS*24-1:0] acc_out
);
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row
            for (c = 0; c < COLS; c = c + 1) begin : col
                int4_mac_v11 mac (
                    .clk(clk), .rst_n(rst_n), .en(en), .clear(clear), .drain(drain),
                    .a(activations[r*4 +: 4]),
                    .b(weights[c*4 +: 4]),
                    .acc(acc_out[(r*COLS + c)*24 +: 24])
                );
            end
        end
    endgenerate
endmodule
