`timescale 1ns/1ps
module tb_x7_top;
 reg clk=0;always #1 clk=~clk;reg rst_n=0;
 reg in_valid=0,in_last=0,out_ready=1;reg[127:0]in_data=0;wire in_ready,out_valid,out_last;wire[127:0]out_data;
 reg weight_prog_en=0;reg[1:0]weight_prog_matrix=0,weight_prog_bank=0;reg[8:0]weight_prog_addr=0;reg[63:0]weight_prog_data=0;
 reg state_prog_en=0,state_prog_bank=0;reg[1:0]state_prog_lane=0;reg[8:0]state_prog_addr=0;reg[63:0]state_prog_data=0;
 reg conv_prog_en=0;reg[6:0]conv_prog_channel=0;reg[31:0]conv_prog_alpha=0,conv_prog_beta=0;
 reg state_debug_en=0,state_debug_bank=0;reg[8:0]state_debug_addr=0;wire[255:0]state_debug_data;wire busy,fault;
 reg[127:0]x1[0:7],x2[0:7],gy1[0:7],gy2[0:7];reg[63:0]weights[0:8191],s0[0:2047],s1[0:2047],s2[0:2047];reg[31:0]ca[0:127],cb[0:127];
 integer m,b,a,j,outs,fail=0,cycles=0;reg[127:0]expected;
 x7_top dut(.*);
 always@(posedge clk)if(rst_n)cycles<=cycles+1;
 task program_all;begin
  for(m=0;m<4;m=m+1)for(a=0;a<512;a=a+1)for(b=0;b<4;b=b+1)begin
   @(negedge clk);weight_prog_en=1;weight_prog_matrix=m;weight_prog_bank=b;weight_prog_addr=a;weight_prog_data=weights[m*2048+a*4+b];
  end
  @(negedge clk);weight_prog_en=0;
  for(a=0;a<512;a=a+1)for(b=0;b<4;b=b+1)begin
   @(negedge clk);state_prog_en=1;state_prog_bank=0;state_prog_lane=b;state_prog_addr=a;state_prog_data=s0[a*4+b];
  end
  @(negedge clk);state_prog_en=0;
  for(a=0;a<128;a=a+1)begin@(negedge clk);conv_prog_en=1;conv_prog_channel=a;conv_prog_alpha=ca[a];conv_prog_beta=cb[a];end
  @(negedge clk);conv_prog_en=0;
 end endtask
 task run_token;input integer which;begin
  for(j=0;j<8;j=j+1)begin @(negedge clk);if(!in_ready)begin $display("input not ready");fail=fail+1;end in_valid=1;in_data=which?x2[j]:x1[j];in_last=(j==7);end
  @(negedge clk);in_valid=0;in_last=0;outs=0;
  while(outs<8)begin @(negedge clk);if(out_valid)begin expected=which?gy2[outs]:gy1[outs];if(out_data!==expected)begin $display("FAIL token %0d beat %0d got %h exp %h",which,outs,out_data,expected);fail=fail+1;end if(out_last!==(outs==7))begin $display("FAIL last");fail=fail+1;end outs=outs+1;end end
  wait(!busy);@(negedge clk);
 end endtask
 task check_state;input integer which;reg[255:0]exp;begin
  state_debug_en=1;state_debug_bank=0;
  for(a=0;a<512;a=a+1)begin
   state_debug_addr=a;@(posedge clk);@(negedge clk);exp=which?{s2[a*4+3],s2[a*4+2],s2[a*4+1],s2[a*4]}:{s1[a*4+3],s1[a*4+2],s1[a*4+1],s1[a*4]};
   if(state_debug_data!==exp)begin if(fail<20)$display("FAIL state token %0d addr %0d got %h exp %h",which,a,state_debug_data,exp);fail=fail+1;end
  end
  state_debug_en=0;@(negedge clk);
 end endtask
 initial begin
  $readmemh("experiments/x7/tb/vectors/x1.mem",x1);$readmemh("experiments/x7/tb/vectors/x2.mem",x2);$readmemh("experiments/x7/tb/vectors/y1.mem",gy1);$readmemh("experiments/x7/tb/vectors/y2.mem",gy2);
  $readmemh("experiments/x7/tb/vectors/weights.mem",weights);$readmemh("experiments/x7/tb/vectors/state0.mem",s0);$readmemh("experiments/x7/tb/vectors/state1.mem",s1);$readmemh("experiments/x7/tb/vectors/state2.mem",s2);$readmemh("experiments/x7/tb/vectors/conv_a.mem",ca);$readmemh("experiments/x7/tb/vectors/conv_b.mem",cb);
  repeat(4)@(posedge clk);rst_n=1;program_all();run_token(0);check_state(0);run_token(1);check_state(1);
  if(fault)begin $display("FAIL fault");fail=fail+1;end
  if(gy1[0]===gy2[0]&&gy1[1]===gy2[1]&&gy1[2]===gy2[2]&&gy1[3]===gy2[3]&&gy1[4]===gy2[4]&&gy1[5]===gy2[5]&&gy1[6]===gy2[6]&&gy1[7]===gy2[7])begin $display("FAIL dependency vectors equal");fail=fail+1;end
  if(fail==0)$display("PASS tb_x7_top full two-token golden flow cycles=%0d macros=32",cycles);else $display("FAIL tb_x7_top errors=%0d cycles=%0d final_phase=%0d",fail,cycles,dut.phase);
  $finish_and_return(fail!=0);
 end
 initial begin repeat(150000)@(posedge clk);$display("TIMEOUT phase=%0d",dut.phase);$finish_and_return(1);end
endmodule
