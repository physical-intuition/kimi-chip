`timescale 1ns/1ps
module tb_weight_equivalence;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0; reg [4:0] phase=0; reg valid=0;
 wire [8:0] a,b; wire [31:0] h1,h2,h3,r1,r2,r3;
 dataflow_top dut(clk,rst_n,1'b0,,9'b0,1'b0,,a,,h1,h2,h3);
 reference_top refdut(clk,rst_n,1'b0,,9'b0,1'b0,,b,,r1,r2,r3);
 integer n; reg [16383:0] q,k,v;
 initial begin
   force dut.current_phase=phase; force refdut.current_phase=phase;
   force dut.mac_pipe_v=valid; force refdut.mac_pipe_v=valid;
   repeat(2) @(negedge clk); rst_n=1;
   for(n=0;n<12000;n=n+1) begin
     phase=($urandom%5==0)?5'd10:($urandom%5);
     valid=$urandom%2;
     @(posedge clk); #1;
     q=dut.weight_q_pending[0]?{4'b0,dut.weight_q_sr[16383:4]}:dut.weight_q_sr;
     k=dut.weight_k_pending[0]?{4'b0,dut.weight_k_sr[16383:4]}:dut.weight_k_sr;
     v=dut.weight_v_pending[0]?{4'b0,dut.weight_v_sr[16383:4]}:dut.weight_v_sr;
     if(q!==refdut.weight_q_sr || k!==refdut.weight_k_sr || v!==refdut.weight_v_sr)
       $fatal(1,"weight logical-state mismatch at %0d",n);
     if(dut.weight_q_head!==refdut.weight_q_head ||
        dut.weight_k_head!==refdut.weight_k_head ||
        dut.weight_v_head!==refdut.weight_v_head) $fatal(1,"head mismatch");
     @(negedge clk);
   end
   $display("PASS 12000 randomized distributed weight-shift equivalence cycles");
   $finish;
 end
endmodule
