`timescale 1ns/1ps
module tb_mac_pipeline;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,start=0; reg [3:0] a=0,b=0;
 wire [23:0] acc; wire done;
 mac_array dut(clk,rst_n,start,a,b,acc,done);
 integer n, count=0, group_sum=0, expected_acc=0, due=-1, cycle=0, outputs=0;
 reg [23:0] expected_queue[0:4095];
 integer due_queue[0:4095], wr=0, rd=0;
 task step;
 begin
   @(posedge clk);
   cycle=cycle+1;
   if(!rst_n) begin
     count=0;group_sum=0;expected_acc=0;wr=0;rd=0;
   end else if(start) begin
     group_sum=group_sum+a*b;
     count=count+1;
     if(count==16) begin
       expected_acc=(expected_acc+group_sum)&24'hffffff;
       expected_queue[wr]=expected_acc;
       due_queue[wr]=cycle+2;
       wr=wr+1; count=0; group_sum=0;
     end
   end
   #1;
   if(!rst_n) begin
     if(done!==0 || acc!==0) $fatal(1,"reset did not clear pipeline");
   end else begin
     if(rd<wr && due_queue[rd]==cycle) begin
       if(done!==1 || acc!==expected_queue[rd])
         $fatal(1,"pipeline result mismatch cycle%0d acc%0d expected%0d done%b",cycle,acc,expected_queue[rd],done);
       rd=rd+1;outputs=outputs+1;
     end else if(done!==0) $fatal(1,"unexpected done");
   end
   @(negedge clk);
 end
 endtask
 initial begin
   step;step;rst_n=1;
   // Exhaust every unsigned operand pair, including back-to-back folds.
   for(n=0;n<256;n=n+1) begin
     start=1;a=n/16;b=n%16;step;
   end
   start=0;repeat(4) step;
   // Random bubbles and reset aborts across pipeline stages.
   for(n=0;n<20000;n=n+1) begin
     rst_n=(n%997!=0);
     start=($urandom%4!=0);a=$urandom;b=$urandom;
     step;
   end
   rst_n=1;start=0;repeat(5) step;
   if(rd!=wr) $fatal(1,"undrained queue");
   $display("PASS exhaustive 256 INT4 products, 20000 random cycles/reset-aborts, %0d fold results",outputs);
   $finish;
 end
endmodule
