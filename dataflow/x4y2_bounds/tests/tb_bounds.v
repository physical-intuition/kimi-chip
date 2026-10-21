`timescale 1ns/1ps
module tb_bounds;
reg clk=0; always #5 clk=~clk;
reg rst=0,tv=0,ss=0; reg[8:0] tid=0;
wire ready,ov,busy;wire[8:0] oid;wire[31:0] a,b,c;
dataflow_top dut(clk,rst,tv,ready,tid,ss,ov,oid,busy,a,b,c);
integer writes=0,scores=0,cycles=0;
initial begin
 repeat(2) @(negedge clk);rst=1;
 @(negedge clk);tv=1;ss=1;
 @(negedge clk);tv=0;ss=0;
 wait(ov); @(negedge clk);
 if(writes!=32 || scores!=1) $fatal(1,"writes=%0d scores=%0d",writes,scores);
 // Full cache refuses another token, but permits explicit restart.
 dut.mla_kv_count=64; #1;
 if(ready) $fatal(1,"full cache accepted token");
 ss=1; #1; if(!ready) $fatal(1,"restart blocked");
 tv=1; @(negedge clk); tv=0; ss=0;
 if(dut.mla_kv_count!=0) $fatal(1,"restart failed");
 $display("PASS query bounds, valid-entry traversal, cache capacity");$finish;
end
always @(posedge clk) if(rst) begin
 cycles=cycles+1;if(cycles>1000000)$fatal(1,"timeout");
 if(dut.current_phase==10 && dut.mac_pipe_v && dut.mac_in_idx==63) begin
  writes=writes+1;
  if(dut.mac_out_idx>=32)$fatal(1,"query output bounds");
 end
 if(dut.current_phase==13) begin
  if(dut.attn_kv_idx>=dut.mla_kv_count)$fatal(1,"unwritten cache entry");
  if(dut.mac_pipe_v && dut.attn_dim_idx==127)scores=scores+1;
 end
end
endmodule
