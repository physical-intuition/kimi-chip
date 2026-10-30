`timescale 1ns/1ps
// X4Y4 rewrite of the X4Y2 bounds regression for the functional MLA.
// Every cycle: projection writebacks stay inside their matrix, MAC operands
// are never unknown, SRAM writes only touch the entry being appended, SRAM
// reads only touch valid entries (< count), consumed read data is known, and
// the SRAM is idle outside append/attention. Per token: every MLA matrix
// writes each output once, 2*T scores and 2*T*16 value words are consumed.
// Then: a full cache refuses tokens but accepts an explicit restart.
module tb_bounds;
reg clk=0; always #5 clk=~clk;
reg rst=0,tv=0,ss=0; reg[8:0] tid=0;
wire ready,ov,busy;wire[8:0] oid;wire[31:0] a,b,c;
dataflow_top dut(clk,rst,tv,ready,tid,ss,ov,oid,busy,a,b,c);
integer cycles=0, m, scores=0, vwords=0, T;
integer writes [0:15];
integer nout [0:15];
reg [4:0] prev_phase=0; reg [7:0] prev_count=0;
task send; input [8:0] t; input s; begin
 @(negedge clk); tv=1; ss=s; tid=t;
 @(negedge clk); tv=0; ss=0;
 wait(ov); @(negedge clk);
end endtask
task check_token; input integer t; begin
 for (m=9; m<16; m=m+1) if (writes[m] != nout[m]) $fatal(1,"matrix %0d wrote %0d of %0d outputs",m,writes[m],nout[m]);
 if (scores != 2*t) $fatal(1,"scores=%0d for T=%0d",scores,t);
 if (vwords != 2*16*t) $fatal(1,"value words=%0d for T=%0d",vwords,t);
 for (m=0; m<16; m=m+1) writes[m]=0;
 scores=0; vwords=0;
end endtask
initial begin
 for (m=0; m<16; m=m+1) begin writes[m]=0; nout[m]=0; end
 nout[9]=128; nout[10]=64; nout[11]=32; nout[12]=16; nout[13]=64; nout[14]=64; nout[15]=64;
 repeat(2) @(negedge clk);rst=1;
 send(0,1); if (dut.mla_kv_count!=1) $fatal(1,"count after first token"); check_token(1);
 send(5,0); if (dut.mla_kv_count!=2) $fatal(1,"count after second token"); check_token(2);
 // Full cache refuses another token, but permits explicit restart.
 dut.mla_kv_count=64; #1;
 if(ready) $fatal(1,"full cache accepted token");
 ss=1; #1; if(!ready) $fatal(1,"restart blocked");
 tv=1; @(negedge clk); tv=0; ss=0;
 if(dut.mla_kv_count!=0) $fatal(1,"restart failed");
 wait(ov); @(negedge clk); if (dut.mla_kv_count!=1) $fatal(1,"count after restart"); check_token(1);
 $display("PASS MLA output bounds, valid-entry SRAM traversal, append bounds, cache capacity, restart");$finish;
end
always @(posedge clk) if(rst) begin
 cycles=cycles+1;if(cycles>2000000)$fatal(1,"timeout");
 if(dut.mac_start===1'b1 && (^dut.mac_a===1'bx || ^dut.mac_b===1'bx)) $fatal(1,"unknown MAC operand");
 if(dut.pj_wb) begin
  if(dut.pj_wb_m>=9) begin
   if(dut.pj_wb_o>=nout[dut.pj_wb_m]) $fatal(1,"matrix %0d output index %0d",dut.pj_wb_m,dut.pj_wb_o);
   writes[dut.pj_wb_m]=writes[dut.pj_wb_m]+1;
  end
 end
 // SRAM controls seen now were issued last cycle (phase prev_phase, count prev_count)
 if(dut.kv_sram_ce) begin
  if(dut.kv_sram_we) begin
   if(prev_phase!=12) $fatal(1,"SRAM write outside append");
   if(dut.kv_sram_addr/72 != prev_count || prev_count>=64) $fatal(1,"append write to entry %0d, count %0d",dut.kv_sram_addr/72,prev_count);
  end else begin
   if(prev_phase!=13 && prev_phase!=15) $fatal(1,"SRAM read outside attention");
   if(dut.kv_sram_addr >= prev_count*72) $fatal(1,"read of unwritten cache word %0d (count %0d)",dut.kv_sram_addr,prev_count);
  end
 end
 if(dut.current_phase==13 && dut.tg2_v) begin
  if(^dut.kv_sram_rdata===1'bx) $fatal(1,"unknown key word consumed");
  if(dut.tg2_w==23) scores=scores+1;
 end
 if(dut.current_phase==15 && dut.tg2_v) begin
  if(^dut.kv_sram_rdata===1'bx) $fatal(1,"unknown value word consumed");
  vwords=vwords+1;
 end
 prev_phase=dut.current_phase; prev_count=dut.mla_kv_count;
end
endmodule
