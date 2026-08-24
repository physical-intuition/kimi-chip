// tb_fullchip_v12 - lane-DISTINCT data, unlike tb_fullchip_banks which
// replicates one value across all 16 lanes (blind to lane-slicing bugs).
// v12 adds a per-lane register tree, so every lane carries its own
// sequence and accumulators are checked at scattered (row,col) positions:
// a mis-sliced lane register shows up as a wrong product somewhere.
// Covers: bank crossings (K=700, 1030), residual chunk (K=37),
// restart-after-DONE.
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

module tb_fullchip_v12;
  reg clk=0, rst_n=0, start=0, h_we=0, h_sel=0;
  reg [11:0] h_addr=0; reg [63:0] h_wdata=0;
  reg [15:0] k_dim=0; reg [7:0] r_addr=0;
  wire done; wire [23:0] r_data;
  fullchip_v12 dut(.clk(clk), .rst_n(rst_n), .h_we(h_we), .h_sel(h_sel),
    .h_addr(h_addr), .h_wdata(h_wdata), .start(start), .k_dim(k_dim),
    .done(done), .r_addr(r_addr), .r_data(r_data));
  always #1 clk = ~clk;

  // weight lane c / activation lane r sequences (4-bit, lane-distinct)
  function [3:0] wl; input integer i; input integer c; wl = i*13 + 1 + 5*c; endfunction
  function [3:0] al; input integer i; input integer r; al = i*7 + 3 + 3*r; endfunction
  function integer sx; input [3:0] v; sx = v[3] ? v - 16 : v; endfunction

  integer i, r, c, t0, cycles, fails;
  reg [63:0] w_word, a_word;

  task load(input sel, input [11:0] a, input [63:0] d);
    begin @(negedge clk); h_we=1; h_sel=sel; h_addr=a; h_wdata=d; @(negedge clk); h_we=0; end
  endtask
  task run_k(input [15:0] K);
    begin
      k_dim = K; @(negedge clk); start=1; @(negedge clk); start=0; t0=$time;
      while (!done) begin #2; if ($time-t0>30000) begin $display("TIMEOUT"); $finish; end end
      cycles = ($time-t0)/2;
    end
  endtask
  task check(input integer rr, input integer cc, input integer K);
    integer e;
    begin
      e = 0; for (i=0; i<K; i=i+1) e = e + sx(al(i,rr))*sx(wl(i,cc));
      r_addr = rr*16 + cc; #4;
      $display("K=%0d acc[%0d][%0d]=%0d exp=%0d %s", K, rr, cc,
        $signed(r_data), e, ($signed(r_data)===e)?"PASS":"FAIL");
      if ($signed(r_data) !== e) fails = fails + 1;
    end
  endtask

  initial begin
    fails = 0;
    #4 rst_n = 1;
    for (i=0; i<1100; i=i+1) begin
      for (c=0; c<16; c=c+1) w_word[c*4 +: 4] = wl(i,c);
      for (r=0; r<16; r=r+1) a_word[r*4 +: 4] = al(i,r);
      load(0, i[11:0], w_word);
      load(1, i[11:0], a_word);
    end
    run_k(700);  $display("K=700 cycles=%0d (expect ~K+8)", cycles);
    check(0,0,700); check(7,7,700); check(15,15,700); check(3,12,700);
    run_k(1030);
    check(0,0,1030); check(7,7,1030); check(15,15,1030); check(3,12,1030);
    run_k(37);   // residual chunk (37 = 2*16 + 5)
    check(0,0,37); check(7,7,37); check(3,12,37);
    run_k(700);  // restart after terminal DONE
    check(7,7,700);
    if (fails == 0) $display("ALL PASS"); else $display("FAILS=%0d", fails);
    $finish;
  end
endmodule
