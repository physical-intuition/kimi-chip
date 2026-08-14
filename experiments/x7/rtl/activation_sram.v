`timescale 1ns/1ps
// Four physical 64-bit macros arranged as two independently-addressed 128-bit
// banks.  Each port is synchronous; rd_out changes one clock after an enabled
// read.  The legacy single-port pins map to port A, so existing programming
// and top-level users remain source-compatible while Y2 controllers can use
// the independent B side for overlapping read/write traffic.
module activation_sram(
 input wire clk,input wire en,input wire we,input wire buffer_sel,
 input wire [8:0] addr,input wire [127:0] wdata,output wire [127:0] rdata,
 input wire en_b,input wire we_b,input wire buffer_sel_b,input wire [8:0] addr_b,
 input wire [127:0] wdata_b,output wire [127:0] rdata_b
);
 wire [63:0] qa[0:3];
 reg rd_sel_a,rd_sel_b;
 always @(posedge clk) begin
  if(en && !we) rd_sel_a <= buffer_sel;
  if(en_b && !we_b) rd_sel_b <= buffer_sel_b;
 end
 genvar k,b;
 generate for(k=0;k<2;k=k+1) begin:gk for(b=0;b<2;b=b+1) begin:gb
   wire a_sel=en && (buffer_sel==k);
   wire b_sel=en_b && (buffer_sel_b==k);
   // One physical macro has one port.  The controller deliberately avoids
   // same-bank A/B collisions; A has deterministic priority if one occurs.
   wire use_a=a_sel;
   wire use_b=b_sel && !a_sel;
   fakeram45_512x64 ram(.clk(clk),.ce_in(use_a|use_b),
     .we_in((use_a&&we)|(use_b&&we_b)),
     .addr_in(use_a?addr:addr_b),.wd_in(use_a?wdata[b*64 +:64]:wdata_b[b*64 +:64]),
     .rd_out(qa[k*2+b]));
 end end endgenerate
 assign rdata={qa[rd_sel_a*2+1],qa[rd_sel_a*2]};
 assign rdata_b={qa[rd_sel_b*2+1],qa[rd_sel_b*2]};
endmodule
