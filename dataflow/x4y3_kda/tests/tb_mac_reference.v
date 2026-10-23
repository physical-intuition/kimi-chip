module tb_mac_reference;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,start=0; reg [3:0] a=0,b=0;
 wire [23:0] acc; wire done;
 mac_array dut(clk,rst_n,start,a,b,acc,done);
 integer i,expected;
 initial begin
   repeat(2) @(negedge clk); rst_n=1;
   expected=0;
   for(i=0;i<16;i=i+1) begin
     @(negedge clk); start=1; a=15; b=15; expected=expected+225;
   end
   @(negedge clk); start=0;
   repeat(4) @(negedge clk);
   if(acc !== expected) $fatal(1,"unsigned INT4 reference mismatch actual=%0d expected=%0d",acc,expected);
   $display("PASS unsigned MAC reference"); $finish;
 end
endmodule
