`timescale 1ns/1ps
module tb_x8_sram;
 reg clk=0;always #5 clk=~clk;reg[5:0]rd_en=0;reg[47:0]rd_addr=0;wire[1535:0]rd_data;
 reg prog_en=0;reg[2:0]prog_bank=0;reg[7:0]prog_addr=0;reg[255:0]prog_data=0;
 reg s_rd_en=0,s_rd_bank=0;reg[6:0]s_rd_row=0;wire[3071:0]s_rd_data;
 reg s_wr_en=0,s_wr_bank=0;reg[6:0]s_wr_row=0;reg[3071:0]s_wr_data=0;
 integer b,failures=0;
 weight_sram_6bank w(.*);
 state_sram_pingpong s(.clk(clk),.rd_en(s_rd_en),.rd_bank(s_rd_bank),.rd_row(s_rd_row),.rd_data(s_rd_data),.wr_en(s_wr_en),.wr_bank(s_wr_bank),.wr_row(s_wr_row),.wr_data(s_wr_data));
 initial begin
  for(b=0;b<6;b=b+1)begin @(negedge clk);prog_en=1;prog_bank=b;prog_addr=8'd200;prog_data={248'd0,b[7:0]};end
  @(negedge clk);prog_en=0;rd_en=6'h3f;for(b=0;b<6;b=b+1)rd_addr[b*8+:8]=8'd200;
  @(negedge clk);#1;for(b=0;b<6;b=b+1)if(rd_data[b*256+:8]!==b[7:0])begin $display("FAIL weight bank %0d",b);failures=failures+1;end
  s_rd_en=0;s_wr_en=1;s_wr_bank=0;s_wr_row=7;s_wr_data={12{256'h1234}};@(negedge clk);
  s_wr_bank=1;s_wr_data={12{256'h5678}};@(negedge clk);s_wr_en=0;s_rd_en=1;s_rd_bank=0;s_rd_row=7;@(negedge clk);#1;
  if(s_rd_data[15:0]!==16'h1234)begin $display("FAIL state bank0");failures=failures+1;end
  s_rd_bank=1;@(negedge clk);#1;if(s_rd_data[15:0]!==16'h5678)begin $display("FAIL state bank1");failures=failures+1;end
  if(failures==0)$display("PASS X8 SRAM: all six 256-deep weight banks and both 48KiB state banks");
  $finish_and_return(failures!=0);
 end
endmodule
