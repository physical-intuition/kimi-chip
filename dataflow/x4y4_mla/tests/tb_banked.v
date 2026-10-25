module tb;
 reg clk=0; always #5 clk=~clk;
 reg ce=0,we=0; reg [10:0] addr=0; reg [63:0] wd=0;
 wire [63:0] rd;
 kv_banked_2048x64 dut(clk,ce,we,addr,wd,64'hffffffffffffffff,rd);
 integer i;
 initial begin
  for(i=0;i<2048;i=i+1) begin
   @(negedge clk); ce=1;we=1;addr=i;wd=64'hface000000000000+i;
  end
  @(negedge clk); we=0;
  for(i=0;i<2048;i=i+1) begin
   addr=i; @(posedge clk); #1;
   if(rd !== 64'hface000000000000+i) $fatal(1,"alias/read failure at %d got %h",i,rd);
   @(negedge clk);
  end
  ce=0; addr=0; @(posedge clk); #1;
  if(rd !== 64'hface0000000007ff) $fatal(1,"disabled read changed");
  $display("PASS 2048 unique addresses, all bank boundaries, CE hold"); $finish;
 end
endmodule
