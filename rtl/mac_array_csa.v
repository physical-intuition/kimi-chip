// CSA-based MAC Array
module mac_array_csa #(
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
        for (r = 0; r < ROWS; r = r + 1) begin : row
            for (c = 0; c < COLS; c = c + 1) begin : col
                mac_csa u_mac (
                    .clk(clk), .rst_n(rst_n), .en(en), .clear(clear),
                    .a(act_in[r*4 +: 4]),
                    .w(wgt_in[c*4 +: 4]),
                    .acc_out(acc_out[(r*COLS + c)*16 +: 16])
                );
            end
        end
    endgenerate

endmodule
