module tb_protocol;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,token_valid=0,seq_start=0; reg [8:0] token_id=7;
 wire ready,valid,busy; wire [8:0] id; wire [31:0] h1,h2,h3;
 dataflow_top dut(clk,rst_n,token_valid,ready,token_id,seq_start,valid,id,busy,h1,h2,h3);
 integer cycles;
 initial begin
   repeat(2) @(negedge clk); rst_n=1;
   @(negedge clk); token_valid=1; seq_start=1;
   @(negedge clk); token_valid=0; seq_start=0;
   cycles=0;
   while(valid!==1 && cycles<1000000) begin @(negedge clk); cycles=cycles+1; end
   if(valid!==1) $fatal(1,"completion timeout");
   @(negedge clk);
   if(valid!==0) $fatal(1,"output_valid not a pulse");
   $display("PASS completion pulse after %0d cycles",cycles);
   $finish;
 end
endmodule
