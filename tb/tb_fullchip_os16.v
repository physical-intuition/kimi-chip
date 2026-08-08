// tb_fullchip_os16 - systolic core vs the same independent reference the
// broadcast cores are held to. Lane-distinct data; chunk hazards: K=16
// (one exact chunk), K=32 (chunk boundary), K=37 (residual 5 -> zero-row
// gating), K=700/1030 (many chunks, bank-group crossings), restart, and
// an accum pass (C(700)+C(330)).
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

module tb_fullchip_os16;
  reg clk=0, rst_n=0, start=0, accum=0, h_we=0, h_sel=0;
  reg [11:0] h_addr=0; reg [63:0] h_wdata=0;
  reg [15:0] k_dim=0; reg [7:0] r_addr=0;
  wire done; wire [23:0] r_data;
  fullchip_os16 dut(.clk(clk), .rst_n(rst_n), .h_we(h_we), .h_sel(h_sel),
    .h_addr(h_addr), .h_wdata(h_wdata), .start(start), .accum(accum),
    .k_dim(k_dim), .done(done), .r_addr(r_addr), .r_data(r_data));
  always #1 clk = ~clk;

  function [3:0] wl; input integer i; input integer c; wl = i*13 + 1 + 5*c; endfunction
  function [3:0] al; input integer i; input integer r; al = i*7 + 3 + 3*r; endfunction
  function integer sx; input [3:0] v; sx = v[3] ? v - 16 : v; endfunction

  integer i, r, c, t0, cycles, fails;
  reg [63:0] w_word, a_word;

  task load(input sel, input [11:0] a, input [63:0] d);
    begin @(negedge clk); h_we=1; h_sel=sel; h_addr=a; h_wdata=d; @(negedge clk); h_we=0; end
  endtask
  task run_k(input [15:0] K, input acc_keep);
    begin
      k_dim = K; accum = acc_keep;
      @(negedge clk); start=1; @(negedge clk); start=0; t0=$time;
      while (!done) begin #2; if ($time-t0>60000) begin $display("TIMEOUT"); $finish; end end
      cycles = ($time-t0)/2;
    end
  endtask
  // expected acc = C(Ka) + C(Kb)  (Kb = 0 for single-pass checks)
  task check(input integer rr, input integer cc, input integer Ka, input integer Kb,
             input [127:0] tag);
    integer e;
    begin
      e = 0;
      for (i=0; i<Ka; i=i+1) e = e + sx(al(i,rr))*sx(wl(i,cc));
      for (i=0; i<Kb; i=i+1) e = e + sx(al(i,rr))*sx(wl(i,cc));
      r_addr = rr*16 + cc; #4;
      $display("%-10s acc[%0d][%0d]=%0d exp=%0d %s", tag, rr, cc,
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
    run_k(16, 0);   check(0,0,16,0,"K=16"); check(7,7,16,0,"K=16"); check(15,15,16,0,"K=16");
    run_k(32, 0);   check(0,0,32,0,"K=32"); check(3,12,32,0,"K=32");
    run_k(37, 0);   check(0,0,37,0,"K=37"); check(7,7,37,0,"K=37"); check(3,12,37,0,"K=37");
    run_k(700, 0);  $display("K=700 cycles=%0d (output-stationary; expect ~K+45)", cycles);
    check(0,0,700,0,"K=700"); check(7,7,700,0,"K=700");
    check(15,15,700,0,"K=700"); check(3,12,700,0,"K=700");
    run_k(1030, 0); check(0,0,1030,0,"K=1030"); check(15,15,1030,0,"K=1030");
    check(3,12,1030,0,"K=1030");
    run_k(700, 0);  run_k(330, 1);   // accum pass on top
    check(0,0,700,330,"accum"); check(7,7,700,330,"accum"); check(3,12,700,330,"accum");
    run_k(700, 0);  check(7,7,700,0,"restart");
    if (fails == 0) $display("ALL PASS"); else $display("FAILS=%0d", fails);
    $finish;
  end
endmodule
