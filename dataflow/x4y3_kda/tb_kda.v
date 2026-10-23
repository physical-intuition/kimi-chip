`timescale 1ns/1ps
// X4Y3: drive a token sequence with restarts; dump every KDA tensor at each
// completion for exact comparison against kda_model.int_step (golden_kda.py).
module tb_kda;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, tv=0, ss=0; reg [8:0] tid=0;
wire ready, ov, busy; wire [8:0] oid; wire [31:0] h1,h2,h3;
dataflow_top dut(clk,rst_n,tv,ready,tid,ss,ov,oid,busy,h1,h2,h3);
integer fd, n, i, cycles=0, start_cycle;
reg [1023:0] path;
reg [8:0] toks [0:5]; reg sss [0:5];
task dumpvec; input [8*8-1:0] name; input integer which; integer j; begin
  $fwrite(fd, "%0s", name);
  for (j=0; j<64; j=j+1) case (which)
    0: $fwrite(fd, " %0d", $signed(dut.kda_q[j*32 +: 32]));
    1: $fwrite(fd, " %0d", $signed(dut.kda_k[j*32 +: 32]));
    2: $fwrite(fd, " %0d", $signed(dut.kda_v[j*32 +: 32]));
    3: $fwrite(fd, " %0d", dut.kda_alpha[j]);
    4: $fwrite(fd, " %0d", dut.kda_f[j]);
    5: $fwrite(fd, " %0d", dut.kda_z[j]);
    6: $fwrite(fd, " %0d", dut.kda_attn[j]);
    7: $fwrite(fd, " %0d", dut.kda_y[j]);
    8: $fwrite(fd, " %0d", dut.kda_out[j]);
  endcase
  $fwrite(fd, "\n");
end endtask
initial begin
 if (!$value$plusargs("TRACE=%s",path)) $fatal(1,"TRACE required");
 fd=$fopen(path,"w");
 toks[0]=0; sss[0]=1; toks[1]=1; sss[1]=0; toks[2]=511; sss[2]=0;
 toks[3]=7; sss[3]=0; toks[4]=42; sss[4]=1; toks[5]=3; sss[5]=0;
 repeat(2) @(negedge clk); rst_n=1;
 for(n=0;n<6;n=n+1) begin
  @(negedge clk); tv=1; ss=sss[n]; tid=toks[n]; start_cycle=cycles;
  @(negedge clk); tv=0; ss=0;
  wait(ov===1); #1;
  $fwrite(fd, "TOKEN %0d %0d %0d\n", toks[n], sss[n], cycles-start_cycle);
  dumpvec("q",0); dumpvec("k",1); dumpvec("v",2); dumpvec("alpha",3); dumpvec("f",4);
  dumpvec("z",5); dumpvec("attn",6); dumpvec("y",7); dumpvec("out",8);
  $fwrite(fd, "beta %0d %0d\n", dut.kda_beta[0], dut.kda_beta[1]);
  $fwrite(fd, "hist");
  for(i=0;i<576;i=i+1) $fwrite(fd, " %0d", dut.conv_hist[i]);
  $fwrite(fd, "\nS");
  for(i=0;i<2048;i=i+1) $fwrite(fd, " %0d", $signed(dut.kda_state[0][i*32 +: 32]));
  $fwrite(fd, "\n");
  @(negedge clk);
 end
 $fclose(fd); $finish;
end
always @(posedge clk) begin cycles=cycles+1; if(cycles>5000000) $fatal(1,"timeout"); end
endmodule
