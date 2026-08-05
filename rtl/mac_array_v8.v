module mac_array_v8 #(
    parameter ROWS = 16,
    parameter COLS = 16
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire [ROWS*4-1:0] activations,
    input wire [COLS*4-1:0] weights,
    output wire [ROWS*COLS*8-1:0] acc_out
);
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row
            for (c = 0; c < COLS; c = c + 1) begin : col
                int4_mac_v8 mac (
                    .clk(clk), .rst_n(rst_n), .en(en), .clear(clear),
                    .a(activations[r*4 +: 4]),
                    .w(weights[c*4 +: 4]),
                    .acc(acc_out[(r*COLS + c)*8 +: 8])
                );
            end
        end
    endgenerate
endmodule
