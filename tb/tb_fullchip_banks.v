`timescale 1ns/1ps
module fakeram45_512x64 (
  input clk, input ce_in, input we_in,
  input [8:0] addr_in, input [63:0] wd_in, input [63:0] w_mask_in,
  output reg [63:0] rd_out);
  reg [63:0] mem [0:511];
  always @(posedge clk) if (ce_in) begin
    if (we_in) mem[addr_in] <= (mem[addr_in] & ~w_mask_in) | (wd_in & w_mask_in);
    else rd_out <= mem[addr_in];
  end
endmodule

module tb_fullchip2;
  reg clk=0, rst_n=0, start=0, h_we=0, h_sel=0;
  reg [11:0] h_addr=0; reg [63:0] h_wdata=0;
  reg [15:0] k_dim=0; reg [7:0] r_addr=0;
  wire done; wire [23:0] r_data;
  fullchip_v10 dut(.clk(clk), .rst_n(rst_n), .h_we(h_we), .h_sel(h_sel),
    .h_addr(h_addr), .h_wdata(h_wdata), .start(start), .k_dim(k_dim),
    .done(done), .r_addr(r_addr), .r_data(r_data));
  always #1 clk = ~clk;
  integer i, exp, t0;
  reg [3:0] av [0:1100]; reg [3:0] wv [0:1100];
  task load(input sel, input [11:0] a, input [63:0] d);
    begin @(negedge clk); h_we=1; h_sel=sel; h_addr=a; h_wdata=d; @(negedge clk); h_we=0; end
  endtask
  task run_k(input [15:0] K, input [127:0] name);
    begin
      exp = 0; for (i=0; i<K; i=i+1) exp = exp + $signed(av[i]) * $signed(wv[i]);
      k_dim = K; @(negedge clk); start=1; @(negedge clk); start=0; t0=$time;
      while (!done) begin #2; if ($time-t0>20000) begin $display("TIMEOUT"); $finish; end end
      r_addr = 0; #4;
      $display("%-14s K=%0d acc=%0d exp=%0d %s cycles=%0d", name, K,
        $signed(r_data), exp, ($signed(r_data)===exp)?"PASS":"FAIL", ($time-t0)/2);
      #6;
    end
  endtask
  initial begin
    #4 rst_n = 1;
    for (i=0; i<1100; i=i+1) begin av[i]=(i*7+3); wv[i]=(i*13+1); end
    for (i=0; i<1100; i=i+1) begin
      load(0, i[11:0], {16{wv[i]}});
      load(1, i[11:0], {16{av[i]}});
    end
    run_k(700,  "cross-1-bank");   // crosses 512: banks 0->1 mid-stream
    run_k(1030, "cross-2-banks");  // crosses 512 and 1024: banks 0->1->2
    // top-bank spot check: write addr 4000-4003 (bank 7), K=4 there? core
    // always reads from 0.. so instead verify write path to bank 7 via a
    // dedicated small run: remap by loading first 4 addrs of bank 7 pattern
    // into 0..3 equivalence is separate; here assert bank7 write does not
    // corrupt bank0 results:
    load(0, 12'd4000, 64'hDEADBEEFDEADBEEF);
    load(1, 12'd4000, 64'hDEADBEEFDEADBEEF);
    run_k(700, "bank7-noalias");   // same expected as cross-1-bank
    $finish;
  end
endmodule
