`timescale 1ns/1ps
// Edge cases: K=1, and back-to-back runs with NO reset between them.
module tb_v10b_extra;
  reg clk=0, rst_n=0, start=0;
  reg [15:0] k_dim;
  reg [3:0] amem [0:63];
  reg [3:0] wmem [0:63];
  always #1 clk = ~clk;

  wire caw, caa, da;  wire [15:0] aaw, aaa; reg [63:0] raw_, raa;
  wire [256*24-1:0] oa;
  always @(posedge clk) begin
    if (caw) raw_ <= {16{wmem[aaw[5:0]]}};
    if (caa) raa  <= {16{amem[aaa[5:0]]}};
  end
  compute_core_v10a duta(.clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
    .wgt_cs(caw), .wgt_addr(aaw), .wgt_rdata(raw_),
    .act_cs(caa), .act_addr(aaa), .act_rdata(raa), .acc_out(oa), .done(da));

  wire cbw, cba, db;  wire [15:0] abw, aba; reg [63:0] rbw, rba;
  wire [256*24-1:0] ob;
  always @(posedge clk) begin
    if (cbw) rbw <= {16{wmem[abw[5:0]]}};
    if (cba) rba <= {16{amem[aba[5:0]]}};
  end
  compute_core_v10b dutb(.clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
    .wgt_cs(cbw), .wgt_addr(abw), .wgt_rdata(rbw),
    .act_cs(cba), .act_addr(aba), .act_rdata(rba), .acc_out(ob), .done(db));

  integer i, exp, t0;
  task run_case(input [15:0] K, input do_reset, input [127:0] name);
    begin
      exp = 0;
      for (i=0; i<K; i=i+1) exp = exp + $signed(amem[i]) * $signed(wmem[i]);
      if (do_reset) begin rst_n = 0; #4 rst_n = 1; end
      k_dim = K; #2 start = 1; #2 start = 0; t0 = $time;
      while (!(da && db)) begin #2; if ($time-t0>4000) begin $display("TIMEOUT %0s", name); $finish; end end
      $display("%-14s K=%0d exp=%0d | v10a=%0d %s | v10b=%0d %s", name, K, exp,
        $signed(oa[23:0]), ($signed(oa[23:0])===exp)?"PASS":"FAIL",
        $signed(ob[23:0]), ($signed(ob[23:0])===exp)?"PASS":"FAIL");
      // let done settle low-high boundaries between cases
      #6;
    end
  endtask
  initial begin
    for (i=0; i<64; i=i+1) begin amem[i]=(i*3+2); wmem[i]=(i*11+5); end
    run_case(1,  1, "K1-fresh");
    run_case(29, 0, "K29-noreset");   // reuse core, no reset
    for (i=0; i<64; i=i+1) begin amem[i]=4'b1000; wmem[i]=4'b0111; end
    run_case(64, 0, "K64-negmax");    // max negative direction, no reset
    run_case(1,  0, "K1-noreset");
    $finish;
  end
endmodule
