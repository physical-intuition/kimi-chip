`timescale 1ns/1ps
// Six 256x256 logical banks, each made from two 128x256 hard macros.
// A packed matrix word has 64 INT4 elements. For element e in a matrix:
// word=e/64, bank=word%6, lane=e%64, local=matrix_base+word/6.
module weight_sram_6bank(
 input wire clk,
 input wire [5:0] rd_en, input wire [47:0] rd_addr,
 output wire [1535:0] rd_data,
 input wire prog_en, input wire [2:0] prog_bank,input wire [7:0] prog_addr,
 input wire [255:0] prog_data
);
 genvar b;
 generate for(b=0;b<6;b=b+1) begin:g_bank
   wire selected=prog_en&&(prog_bank==b);
   wire [7:0] a=selected?prog_addr:rd_addr[b*8+:8];
   wire ce=selected|rd_en[b]; wire we=selected;
   wire [255:0] lo_q,hi_q;
   fakeram45_128x256 lo(.clk(clk),.ce_in(ce&~a[7]),.we_in(we&~a[7]),.addr_in(a[6:0]),.wd_in(prog_data),.w_mask_in({256{1'b1}}),.rd_out(lo_q));
   fakeram45_128x256 hi(.clk(clk),.ce_in(ce&a[7]), .we_in(we&a[7]), .addr_in(a[6:0]),.wd_in(prog_data),.w_mask_in({256{1'b1}}),.rd_out(hi_q));
   assign rd_data[b*256+:256]=a[7]?hi_q:lo_q;
 end endgenerate
endmodule
