// tb_fullchip_os32p - the 32x32 finale against the same independent
// reference. Lane-distinct data across all 32 lanes; checks in every
// array quadrant; chunk/odd-K hazards; the phantom-restart sequence
// (short accum pass then clean restart); throughput check ~K/2+80.
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

module tb_fullchip_os32p;
  reg clk=0, rst_n=0, start=0, accum=0, h_we=0, h_sel=0;
  reg [11:0] h_addr=0; reg [63:0] h_wdata=0;
  reg [15:0] k_dim=0; reg [9:0] r_addr=0;
  wire done; wire [23:0] r_data;
  fullchip_os32p dut(.clk(clk), .rst_n(rst_n), .h_we(h_we), .h_sel(h_sel),
    .h_addr(h_addr), .h_wdata(h_wdata), .start(start), .accum(accum),
    .k_dim(k_dim), .done(done), .r_addr(r_addr), .r_data(r_data));
  always #1 clk = ~clk;

  function [3:0] wl; input integer i; input integer c; wl = i*13 + 1 + 5*c; endfunction
  function [3:0] al; input integer i; input integer r; al = i*7 + 3 + 3*r; endfunction
  function integer sx; input [3:0] v; sx = v[3] ? v - 16 : v; endfunction

  integer i, r, c, t0, cycles, fails;
  reg [63:0] wd;

  task loadw(input sel, input [10:0] e, input half, input [63:0] d);
    begin @(negedge clk); h_we=1; h_sel=sel; h_addr={e, half}; h_wdata=d;
          @(negedge clk); h_we=0; end
  endtask
  task load_elem(input integer e);
    begin
      for (c=0; c<16; c=c+1)  wd[c*4 +: 4] = wl(e,c);
      loadw(0, e[10:0], 1'b0, wd);
      for (c=16; c<32; c=c+1) wd[(c-16)*4 +: 4] = wl(e,c);
      loadw(0, e[10:0], 1'b1, wd);
      for (r=0; r<16; r=r+1)  wd[r*4 +: 4] = al(e,r);
      loadw(1, e[10:0], 1'b0, wd);
      for (r=16; r<32; r=r+1) wd[(r-16)*4 +: 4] = al(e,r);
      loadw(1, e[10:0], 1'b1, wd);
    end
  endtask
  task run_k(input [15:0] K, input acc_keep);
    begin
      k_dim = K; accum = acc_keep;
      @(negedge clk); start=1; @(negedge clk); start=0; t0=$time;
      while (!done) begin #2; if ($time-t0>80000) begin $display("TIMEOUT"); $finish; end end
      cycles = ($time-t0)/2;
    end
  endtask
  task check(input integer rr, input integer cc, input integer Ka, input integer Kb,
             input [127:0] tag);
    integer e;
    begin
      e = 0;
      for (i=0; i<Ka; i=i+1) e = e + sx(al(i,rr))*sx(wl(i,cc));
      for (i=0; i<Kb; i=i+1) e = e + sx(al(i,rr))*sx(wl(i,cc));
      r_addr = rr*32 + cc; #6;
      $display("%-8s acc[%0d][%0d]=%0d exp=%0d %s", tag, rr, cc,
        $signed(r_data), e, ($signed(r_data)===e)?"PASS":"FAIL");
      if ($signed(r_data) !== e) fails = fails + 1;
    end
  endtask

  initial begin
    fails = 0;
    #4 rst_n = 1;
    for (i=0; i<1100; i=i+1) load_elem(i);
    run_k(16, 0);   check(0,0,16,0,"K=16"); check(31,31,16,0,"K=16"); check(20,5,16,0,"K=16");
    run_k(37, 0);   check(7,7,37,0,"K=37"); check(16,15,37,0,"K=37"); check(5,20,37,0,"K=37");
    run_k(700, 0);  $display("K=700 cycles=%0d (expect ~K/2+80=430)", cycles);
    check(0,0,700,0,"K=700"); check(31,31,700,0,"K=700");
    check(15,16,700,0,"K=700"); check(20,5,700,0,"K=700"); check(7,25,700,0,"K=700");
    run_k(1030, 0); check(0,0,1030,0,"K=1030"); check(31,31,1030,0,"K=1030");
    check(5,20,1030,0,"K=1030");
    run_k(700, 0);  run_k(330, 1);
    check(0,0,700,330,"accum"); check(31,31,700,330,"accum"); check(20,5,700,330,"accum");
    run_k(700, 0);  check(7,7,700,0,"restart"); check(31,31,700,0,"restart");
    if (fails == 0) $display("ALL PASS"); else $display("FAILS=%0d", fails);
    $finish;
  end
endmodule
