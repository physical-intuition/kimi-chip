`timescale 1ns/1ps
// Two 128x3072 state banks. Each row is sliced over twelve 128x256 macros.
module state_sram_pingpong(
 input wire clk,
 input wire rd_en,input wire rd_bank,input wire [6:0] rd_row,output wire [3071:0] rd_data,
 input wire wr_en,input wire wr_bank,input wire [6:0] wr_row,input wire [3071:0] wr_data
);
 wire [3071:0] bank_q[0:1];
 genvar bank,s;
 generate for(bank=0;bank<2;bank=bank+1) begin:g_bank
   for(s=0;s<12;s=s+1) begin:g_slice
     wire do_read=rd_en&&(rd_bank==bank); wire do_write=wr_en&&(wr_bank==bank);
     fakeram45_128x256 m(.clk(clk),.ce_in(do_read|do_write),.we_in(do_write),
       .addr_in(do_write?wr_row:rd_row),.wd_in(wr_data[s*256+:256]),
       .w_mask_in({256{1'b1}}),.rd_out(bank_q[bank][s*256+:256]));
   end
 end endgenerate
 assign rd_data=rd_bank?bank_q[1]:bank_q[0];
endmodule
