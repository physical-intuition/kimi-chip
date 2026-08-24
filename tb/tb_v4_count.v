// Does compute_core_v4 add each product once or twice?
// All activations=1, all weights=1, K=4 -> correct acc = 4 per MAC.
// Observed: 7 = elements 0..2 added twice + element 3 once (double-count).
`timescale 1ns/1ps
module tb_v4_count;
  reg clk=0, rst_n=0, start=0;
  wire wgt_cs, act_cs, done;
  wire [5:0] wgt_addr, act_addr;
  wire [256*12-1:0] acc_out;
  wire [63:0] wgt_rdata_c = 64'h1111111111111111;
  wire [63:0] act_rdata_c = 64'h1111111111111111;
  reg  [63:0] wgt_rdata, act_rdata;
  // model sram_sp: registered read, data valid 1 cycle after cs+addr
  always @(posedge clk) begin
    if (wgt_cs) wgt_rdata <= wgt_rdata_c;
    if (act_cs) act_rdata <= act_rdata_c;
  end
  compute_core_v4 dut(.clk(clk), .rst_n(rst_n), .start(start), .k_dim(6'd4),
    .wgt_cs(wgt_cs), .wgt_addr(wgt_addr), .wgt_rdata(wgt_rdata),
    .act_cs(act_cs), .act_addr(act_addr), .act_rdata(act_rdata),
    .acc_out(acc_out), .done(done));
  always #1 clk = ~clk;
  integer i;
  initial begin
    #4 rst_n = 1; #2 start = 1; #2 start = 0;
    for (i=0; i<100 && !done; i=i+1) #2;
    $display("done=%0d  acc[0]=%0d  expected(single-count)=4  (double-count gives 7)",
             done, $signed(acc_out[11:0]));
    $finish;
  end
endmodule
