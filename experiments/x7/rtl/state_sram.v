`timescale 1ns/1ps
// Two 16 KiB state banks, four macros per bank. Read-before-write permits an
// in-place pass-2 update after pass 1 has moved state to the alternate bank.
module state_sram (
 input wire clk,
 input wire prog_en,input wire prog_bank,input wire [1:0] prog_lane,
 input wire [8:0] prog_addr,input wire [63:0] prog_data,
 input wire rd_en,input wire rd_bank,input wire [8:0] rd_addr,
 input wire wr_en,input wire wr_bank,input wire [8:0] wr_addr,input wire [255:0] wr_data,
 output wire [255:0] rd_data
);
 wire [63:0] q[0:7];
 reg rd_bank_q;
 always @(posedge clk) if(rd_en) rd_bank_q <= rd_bank;
 genvar k,b;
 generate for(k=0;k<2;k=k+1) begin:gk
   for(b=0;b<4;b=b+1) begin:gb
     wire p=prog_en&&(prog_bank==k)&&(prog_lane==b);
     wire w=wr_en&&(wr_bank==k);
     wire r=rd_en&&(rd_bank==k);
     wire ce=p|w|r;
     wire we=p|w;
     wire [8:0] a=p?prog_addr:(w?wr_addr:rd_addr);
     wire [63:0] d=p?prog_data:wr_data[b*64 +:64];
     fakeram45_512x64 ram(.clk(clk),.ce_in(ce),.we_in(we),.addr_in(a),.wd_in(d),.rd_out(q[k*4+b]));
   end
 end endgenerate
 assign rd_data={q[rd_bank_q*4+3],q[rd_bank_q*4+2],q[rd_bank_q*4+1],q[rd_bank_q*4+0]};
endmodule
