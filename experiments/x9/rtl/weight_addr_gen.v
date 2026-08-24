`timescale 1ns/1ps
// Row-major 128x128 INT4 matrix addressing. Each physical word contains
// 64 consecutive elements and global words are striped over six banks.
module weight_addr_gen(
    input  wire [1:0] matrix,
    input  wire [6:0] row,
    input  wire [6:0] col,
    output reg  [2:0] bank,
    output reg  [7:0] addr,
    output wire [5:0] lane,
    output wire [7:0] word
);
    reg [7:0] matrix_base;
    wire [13:0] element_index = {row, col};
    assign word = element_index[13:6];
    assign lane = element_index[5:0];

    always @* begin
        case (matrix)
            2'd0: matrix_base = 8'd0;
            2'd1: matrix_base = 8'd43;
            2'd2: matrix_base = 8'd86;
            default: matrix_base = 8'd129;
        endcase
        bank = word % 6;
        addr = matrix_base + (word / 6);
    end
endmodule
