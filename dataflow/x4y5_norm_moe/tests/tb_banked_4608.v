// X4Y4: 9-bank KV macro, every address unique, all bank boundaries, CE hold.
module tb_banked_4608;
 reg clk=0; always #5 clk=~clk;
 reg ce=0,we=0; reg [12:0] addr=0; reg [63:0] wd=0;
 wire [63:0] rd;
 kv_banked_4608x64 dut(clk,ce,we,addr,wd,64'hffffffffffffffff,rd);
 integer i;
 initial begin
  for(i=0;i<4608;i=i+1) begin
   @(negedge clk); ce=1;we=1;addr=i;wd=64'hface000000000000+i;
  end
  @(negedge clk); we=0;
  for(i=0;i<4608;i=i+1) begin
   addr=i; @(posedge clk); #1;
   if(rd !== 64'hface000000000000+i) $fatal(1,"alias/read failure at %0d got %h",i,rd);
   @(negedge clk);
  end
  ce=0; addr=0; @(posedge clk); #1;
  if(rd !== 64'hface0000000011ff) $fatal(1,"disabled read changed");
  $display("PASS 4608 unique addresses, 9 banks, CE hold"); $finish;
 end
endmodule
