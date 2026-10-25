`timescale 1ns/1ps
// X4Y4: drive a token sequence (file +SEQ, lines "token seq_start" or
// "PROBE token") with a real valid/ready handshake; at each completion dump
// every KDA tensor (golden_kda.py) and MLA tensor plus the valid KV-cache SRAM
// image (golden_mla.py). PROBE offers a token without seq_start and requires
// that it is refused for 2000 cycles (full-cache backpressure).
module tb_mla;
parameter GROUP_SIZE = 128;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, tv=0, ss=0; reg [8:0] tid=0;
wire ready, ov, busy; wire [8:0] oid; wire [31:0] h1,h2,h3;
dataflow_top #(.GROUP_SIZE(GROUP_SIZE)) dut(clk,rst_n,tv,ready,tid,ss,ov,oid,busy,h1,h2,h3);
integer fd, sf, n, i, j, cycles=0, start_cycle, r, tok, sst, T;
reg [1023:0] path, seqp;
reg [8*8-1:0] kw;
reg [63:0] word;
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
    9: $fwrite(fd, " %0d", dut.mla_hu[j]);
    10: $fwrite(fd, " %0d", dut.mla_qc[j]);
    11: $fwrite(fd, " %0d", dut.mla_kc[j]);
    12: $fwrite(fd, " %0d", dut.mla_v[j]);
    13: $fwrite(fd, " %0d", dut.mla_ctx[j]);
    14: $fwrite(fd, " %0d", dut.mla_ctxu[j]);
    15: $fwrite(fd, " %0d", dut.mla_out[j]);
  endcase
  $fwrite(fd, "\n");
end endtask
function [63:0] cache_word; input integer a; begin
  case (a / 512)
    0: cache_word = dut.kv_sram.banks[0].ram.mem[a % 512];
    1: cache_word = dut.kv_sram.banks[1].ram.mem[a % 512];
    2: cache_word = dut.kv_sram.banks[2].ram.mem[a % 512];
    3: cache_word = dut.kv_sram.banks[3].ram.mem[a % 512];
    4: cache_word = dut.kv_sram.banks[4].ram.mem[a % 512];
    5: cache_word = dut.kv_sram.banks[5].ram.mem[a % 512];
    6: cache_word = dut.kv_sram.banks[6].ram.mem[a % 512];
    7: cache_word = dut.kv_sram.banks[7].ram.mem[a % 512];
    default: cache_word = dut.kv_sram.banks[8].ram.mem[a % 512];
  endcase
end endfunction
initial begin
 if (!$value$plusargs("TRACE=%s",path)) $fatal(1,"TRACE required");
 if (!$value$plusargs("SEQ=%s",seqp)) $fatal(1,"SEQ required");
 fd=$fopen(path,"w"); sf=$fopen(seqp,"r");
 repeat(2) @(negedge clk); rst_n=1;
 n=0;
 while (!$feof(sf)) begin
  r=$fscanf(sf, "%s %d\n", kw, tok);
  if (r != 2) $fatal(1,"bad SEQ line");
  if (kw == "PROBE") begin
   @(negedge clk); tv=1; ss=0; tid=tok;
   for (i=0; i<2000; i=i+1) begin
    @(posedge clk); #1 if (ready || busy) $fatal(1,"full cache accepted a token without seq_start");
   end
   @(negedge clk); tv=0;
   $fwrite(fd, "PROBE %0d %0d\n", tok, dut.mla_kv_count);
  end else begin
   sst=tok; r=$sscanf(kw, "%d", tok);   // line is "token seq_start"
   @(negedge clk); tv=1; ss=sst; tid=tok; start_cycle=cycles;
   @(posedge clk); while (!ready) @(posedge clk);
   @(negedge clk); tv=0; ss=0;
   wait(ov===1); #1;
   T = dut.mla_kv_count;
   $fwrite(fd, "TOKEN %0d %0d %0d\n", tok, sst, cycles-start_cycle);
   dumpvec("q",0); dumpvec("k",1); dumpvec("v",2); dumpvec("alpha",3); dumpvec("f",4);
   dumpvec("z",5); dumpvec("attn",6); dumpvec("y",7); dumpvec("out",8);
   $fwrite(fd, "beta %0d %0d\n", dut.kda_beta[0], dut.kda_beta[1]);
   $fwrite(fd, "hist");
   for(i=0;i<576;i=i+1) $fwrite(fd, " %0d", dut.conv_hist[i]);
   $fwrite(fd, "\nS");
   for(i=0;i<2048;i=i+1) $fwrite(fd, " %0d", $signed(dut.kda_state[0][i*32 +: 32]));
   $fwrite(fd, "\n");
   dumpvec("m_hu",9); dumpvec("m_qc",10); dumpvec("m_kc",11); dumpvec("m_v",12);
   dumpvec("m_ctx",13); dumpvec("m_ctxu",14); dumpvec("m_out",15);
   $fwrite(fd, "m_latr"); for(i=0;i<128;i=i+1) $fwrite(fd, " %0d", dut.mla_latr[i]);
   $fwrite(fd, "\nm_lat"); for(i=0;i<128;i=i+1) $fwrite(fd, " %0d", dut.mla_lat[i]);
   $fwrite(fd, "\nm_latu"); for(i=0;i<128;i=i+1) $fwrite(fd, " %0d", dut.mla_latu[i]);
   $fwrite(fd, "\nm_qr"); for(i=0;i<32;i=i+1) $fwrite(fd, " %0d", dut.mla_qr[i]);
   $fwrite(fd, "\nm_kr"); for(i=0;i<16;i=i+1) $fwrite(fd, " %0d", dut.mla_kr[i]);
   $fwrite(fd, "\nm_e %0d %0d\nm_T %0d", dut.mla_elat, dut.mla_ectx, T);
   $fwrite(fd, "\nm_score"); for(j=0;j<2;j=j+1) for(i=0;i<T;i=i+1) $fwrite(fd, " %0d", dut.mla_score[j*64+i]);
   $fwrite(fd, "\nm_p"); for(j=0;j<2;j=j+1) for(i=0;i<T;i=i+1) $fwrite(fd, " %0d", dut.mla_p[j*64+i]);
   $fwrite(fd, "\nm_kv"); for(i=0;i<T*72;i=i+1) begin word = cache_word(i); $fwrite(fd, " %h", word); end
   $fwrite(fd, "\n");
   n=n+1;
  end
 end
 $fclose(fd); $finish;
end
always @(posedge clk) begin cycles=cycles+1; if(cycles>40000000) $fatal(1,"timeout"); end
endmodule
