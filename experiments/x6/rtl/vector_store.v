`timescale 1ns/1ps
module vector_store #(
    parameter WORD_W = 128,
    parameter DEPTH = 8,
    parameter ADDR_W = 3
) (
    input wire clk,
    input wire write_en,
    input wire [ADDR_W-1:0] write_addr,
    input wire [WORD_W-1:0] write_data,
    output wire [WORD_W*DEPTH-1:0] packed_data
);
    reg [WORD_W-1:0] mem [0:DEPTH-1];
    always @(posedge clk) if (write_en) mem[write_addr] <= write_data;
    genvar i;
    generate for (i=0;i<DEPTH;i=i+1) begin : g_pack
        assign packed_data[i*WORD_W +: WORD_W] = mem[i];
    end endgenerate
endmodule
