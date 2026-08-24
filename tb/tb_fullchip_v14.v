// tb_fullchip_v14 - ping-pong protocol, checked bit-exactly:
//   A: clean pass, tile 0, K=700 (v13 regression on the retiled memory)
//   B: WHILE pass A computes, load tile 1 with elements 700..1029 (the
//      overlap the design exists for); then accum-pass tile 1, K=330;
//      accumulators must equal the full K=1030 reference
//   C: odd-length first pass: clean K=701 (half-pair gate) + accum K=329
//      from the other tile -> same K=1030 reference
//   D: clean restart K=700 -> accumulation state fully cleared
// Lane-distinct data as v13; scattered accumulator checks.
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

module tb_fullchip_v14;
  reg clk=0, rst_n=0, start=0, accum=0, c_tile=0, h_we=0, h_sel=0, h_tile=0;
  reg [10:0] h_addr=0; reg [63:0] h_wdata=0;
  reg [15:0] k_dim=0; reg [7:0] r_addr=0;
  wire done; wire [23:0] r_data;
  fullchip_v14 dut(.clk(clk), .rst_n(rst_n), .h_we(h_we), .h_sel(h_sel),
    .h_tile(h_tile), .h_addr(h_addr), .h_wdata(h_wdata),
    .start(start), .accum(accum), .c_tile(c_tile), .k_dim(k_dim),
    .done(done), .r_addr(r_addr), .r_data(r_data));
  always #1 clk = ~clk;

  function [3:0] wl; input integer i; input integer c; wl = i*13 + 1 + 5*c; endfunction
  function [3:0] al; input integer i; input integer r; al = i*7 + 3 + 3*r; endfunction
  function integer sx; input [3:0] v; sx = v[3] ? v - 16 : v; endfunction

  integer i, r, c, t0, cycles, fails, ld;
  reg [63:0] w_word, a_word;

  // load global element e into tile t at local index i (both operands)
  task load_elem(input tt, input [10:0] li, input integer e);
    begin
      for (c=0; c<16; c=c+1) w_word[c*4 +: 4] = wl(e,c);
      for (r=0; r<16; r=r+1) a_word[r*4 +: 4] = al(e,r);
      @(negedge clk); h_we=1; h_sel=0; h_tile=tt; h_addr=li; h_wdata=w_word;
      @(negedge clk); h_sel=1; h_wdata=a_word;
      @(negedge clk); h_we=0;
    end
  endtask
  task kick(input tt, input acc_keep, input [15:0] K);
    begin @(negedge clk); c_tile=tt; accum=acc_keep; k_dim=K;
          start=1; @(negedge clk); start=0; t0=$time; end
  endtask
  task wait_done;
    begin while (!done) begin #2; if ($time-t0>40000) begin $display("TIMEOUT"); $finish; end end
          cycles = ($time-t0)/2; end
  endtask
  task check(input integer rr, input integer cc, input integer K, input [127:0] tag);
    integer e;
    begin
      e = 0; for (i=0; i<K; i=i+1) e = e + sx(al(i,rr))*sx(wl(i,cc));
      r_addr = rr*16 + cc; #4;
      $display("%-10s K=%0d acc[%0d][%0d]=%0d exp=%0d %s", tag, K, rr, cc,
        $signed(r_data), e, ($signed(r_data)===e)?"PASS":"FAIL");
      if ($signed(r_data) !== e) fails = fails + 1;
    end
  endtask

  initial begin
    fails = 0;
    #4 rst_n = 1;
    // tile 0 <- elements 0..700
    for (i=0; i<=700; i=i+1) load_elem(0, i[10:0], i);

    // A: clean pass tile 0, K=700
    kick(0, 0, 700); wait_done;
    $display("A cycles=%0d (expect ~359)", cycles);
    check(0,0,700,"A:clean"); check(7,7,700,"A:clean"); check(15,15,700,"A:clean");

    // B: compute tile 0 again (clean) and load tile 1 DURING the pass
    kick(0, 0, 700);
    ld = 700;
    while (!done) begin
      if (ld <= 1029) begin load_elem(1, ld-700, ld); ld = ld + 1; end
      else #2;
      if ($time-t0>60000) begin $display("TIMEOUT B"); $finish; end
    end
    if (ld <= 1029) $display("NOTE: pass ended before load finished (%0d loaded)", ld-700);
    while (ld <= 1029) begin load_elem(1, ld-700, ld); ld = ld + 1; end
    check(7,7,700,"B:overlap");                      // pass B unharmed by writes
    kick(1, 1, 330); wait_done;                      // accum pass on tile 1
    check(0,0,1030,"B:accum"); check(7,7,1030,"B:accum");
    check(15,15,1030,"B:accum"); check(3,12,1030,"B:accum");

    // C: odd first pass (701) + accum remainder (329) from retiled data
    for (i=0; i<329; i=i+1) load_elem(1, i[10:0], 701+i);
    kick(0, 0, 701); wait_done;
    check(7,7,701,"C:odd");
    kick(1, 1, 329); wait_done;
    check(0,0,1030,"C:accum"); check(7,7,1030,"C:accum"); check(3,12,1030,"C:accum");

    // D: clean restart drops all accumulation
    kick(0, 0, 700); wait_done;
    check(7,7,700,"D:restart"); check(3,12,700,"D:restart");

    if (fails == 0) $display("ALL PASS"); else $display("FAILS=%0d", fails);
    $finish;
  end
endmodule
