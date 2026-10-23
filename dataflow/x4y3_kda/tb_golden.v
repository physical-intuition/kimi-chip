`timescale 1ns/1ps
module tb_golden;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, tv=0, ss=0; reg [8:0] tid=0;
wire ready, ov, busy; wire [8:0] oid; wire [31:0] h1,h2,h3;
dataflow_top dut(clk,rst_n,tv,ready,tid,ss,ov,oid,busy,h1,h2,h3);
integer fd, cycle=0, n, phase, idx, write_kind, write_idx;
reg [31:0] result;
reg [1023:0] path;
initial begin
 if (!$value$plusargs("TRACE=%s",path)) $fatal(1,"TRACE required");
 fd=$fopen(path,"w");
 repeat(2) @(negedge clk); rst_n=1;
 for(n=0;n<3;n=n+1) begin
  @(negedge clk); tv=1; ss=(n!=1); tid=(n==0)?0:((n==1)?1:511);
  @(negedge clk); tv=0; ss=0;
  wait(ov===1);
 end
 @(negedge clk); $fclose(fd); $finish;
end
always @(posedge clk) if(rst_n) begin
 cycle=cycle+1;
 if(cycle>2000000) $fatal(1,"timeout");
 phase=dut.current_phase;
 write_kind=-1; write_idx=0;
 if(dut.mac_pipe_v) begin
  if(phase==10 && dut.mac_in_idx==63) begin  // X4Y3: KDA writes checked by golden_kda.py
   write_kind=phase; write_idx=dut.mac_out_idx;
  end
  if(phase==13 && dut.attn_dim_idx==127) begin
   write_kind=phase; write_idx=dut.attn_kv_idx;
  end
 end
 $fwrite(fd,"%0d %0d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %0d %0d ",
  cycle,phase,dut.mac_start,dut.mac_a,dut.mac_b,dut.mac_done,dut.mac_acc,
  dut.mac_pipe_v,dut.mac_pipe,dut.kv_sram_ce,dut.kv_sram_we,dut.kv_sram_addr,
  dut.kv_sram_wdata,tv,ss,tid,dut.mla_kv_count,dut.current_layer,write_kind,write_idx);
 #1;
 case(write_kind)
  1: result=dut.kda_q[write_idx*32 +:32];
  2: result=dut.kda_k[write_idx*32 +:32];
  3: result=dut.kda_v[write_idx*32 +:32];
  10: result=dut.mla_q[write_idx*32 +:32];
  13: result=dut.attn_scores[write_idx*32 +:32];
  default: result=0;
 endcase
 $fdisplay(fd,"%h %h %h %h %h %h %h %h %h",
  dut.mac_acc,dut.mac_done,dut.mac_pipe,dut.mac_pipe_v,
  dut.kv_sram_rdata,result,ov,oid,dut.mla_kv_count);
end
endmodule
