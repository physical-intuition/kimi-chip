module mac_array_v5 #(
    parameter ROWS = 8,
    parameter COLS = 32,
    parameter ACC_WIDTH = 16
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire [ROWS*4-1:0] activations,  // 8 activations
    input wire [COLS*4-1:0] weights,       // 32 weights
    output wire [ROWS*COLS*ACC_WIDTH-1:0] acc_out
);
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row
            for (c = 0; c < COLS; c = c + 1) begin : col
                int4_mac_v2 mac (
                    .clk(clk), .rst_n(rst_n), .en(en), .clear(clear),
                    .a(activations[r*4 +: 4]),
                    .w(weights[c*4 +: 4]),
                    .acc(acc_out[(r*COLS + c)*ACC_WIDTH +: ACC_WIDTH])
                );
            end
        end
    endgenerate
endmodule
