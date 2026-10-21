`timescale 1ns/1ps
module tb_debug_latency;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0;
 wire [31:0] h1,h2,h3;
 dataflow_top dut(.clk(clk),.rst_n(rst_n),.token_valid(1'b0),.token_id(9'b0),.seq_start(1'b0),
 .debug_state_hash(h1),.debug_cache_hash(h2),.debug_q_hash(h3));
 reg [63:0] state_word, cache_word, q_word;
 reg [7:0] count;
 integer n;
 initial begin
   @(negedge clk);
   if({h1,h2,h3}!==96'b0) $fatal(1,"debug reset");
   rst_n=1;
   for(n=0;n<100;n=n+1) begin
     state_word={$urandom,$urandom};cache_word={$urandom,$urandom};q_word={$urandom,$urandom};count=$urandom;
     // Icarus cannot force a memory word, so deposit the observable low slice.
     dut.kda_state[0][63:0]=state_word;
     force dut.kv_word_r=cache_word;
     force dut.kda_q=q_word;
     force dut.mla_kv_count=count;
     @(posedge clk);#1;
     if(h1!==(state_word[31:0]^state_word[63:32]) ||
        h2!==(cache_word[31:0]^{24'b0,count}) ||
        h3!==(q_word[31:0]^q_word[63:32])) $fatal(1,"debug sample mismatch");
     @(negedge clk);
   end
   $display("PASS 100 randomized debug hash samples and reset");
   $finish;
 end
endmodule
