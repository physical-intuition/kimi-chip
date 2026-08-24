`timescale 1ns/1ps
// Four explicit 128-byte K/V/Q/O vector stores. Eight serialized projection
// results are packed into one 64-bit word before a single macro write.
module intermediate_sram(
 input wire clk,input wire [3:0] wr_en,input wire [6:0] wr_index,input wire [7:0] wr_data,
 input wire [3:0] rd_en,input wire [5:0] rd_word_addr,output wire [255:0] rd_words
);
 reg [63:0] pack[0:3];reg [3:0] macro_we;reg [5:0] macro_wa;reg [63:0] macro_wd[0:3];
 wire [63:0] q[0:3];integer i;
 always @(posedge clk) begin
  macro_we<=0;
  for(i=0;i<4;i=i+1)if(wr_en[i])begin
   pack[i][wr_index[2:0]*8 +:8]<=wr_data;
   if(wr_index[2:0]==7)begin macro_we[i]<=1;macro_wa<=wr_index[6:3];macro_wd[i]<={wr_data,pack[i][55:0]};end
  end
 end
 genvar g;generate for(g=0;g<4;g=g+1)begin:vm
  (* keep = "true" *) fakeram45_512x64 ram(.clk(clk),.ce_in(macro_we[g]|rd_en[g]),.we_in(macro_we[g]),
   .addr_in(macro_we[g]?{3'd0,macro_wa}:{3'd0,rd_word_addr}),.wd_in(macro_wd[g]),.rd_out(q[g]));
 end endgenerate
 assign rd_words={q[3],q[2],q[1],q[0]};
endmodule
