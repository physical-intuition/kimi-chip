`timescale 1ns/1ps
module tb_v10;
  reg clk=0, rst_n=0, start=0;
  reg [15:0] k_dim;
  reg [3:0] amem [0:63];
  reg [3:0] wmem [0:63];
  always #1 clk = ~clk;

  // --- three DUTs, each with its own registered-read SRAM model ---
  wire c9w, c9a, d9;  wire [15:0] a9w, a9a; reg [63:0] r9w, r9a;
  wire [256*24-1:0] o9;
  always @(posedge clk) begin
    if (c9w) r9w <= {16{wmem[a9w[5:0]]}};
    if (c9a) r9a <= {16{amem[a9a[5:0]]}};
  end
  compute_core_v9 dut9(.clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
    .wgt_cs(c9w), .wgt_addr(a9w), .wgt_rdata(r9w),
    .act_cs(c9a), .act_addr(a9a), .act_rdata(r9a), .acc_out(o9), .done(d9));

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

  integer i, exp, cy9, cya, cyb, t0;
  reg [23:0] g9, ga, gb;
  task run_case(input [15:0] K, input [127:0] name);
    begin
      exp = 0;
      for (i=0; i<K; i=i+1) exp = exp + $signed(amem[i]) * $signed(wmem[i]);
      rst_n = 0; #4 rst_n = 1; k_dim = K; #2 start = 1; #2 start = 0; t0 = $time;
      cy9=0; cya=0; cyb=0;
      while (!(d9 && da && db)) begin
        #2;
        if (!d9) cy9 = cy9 + 1;
        if (!da) cya = cya + 1;
        if (!db) cyb = cyb + 1;
        if ($time - t0 > 4000) begin $display("TIMEOUT"); $finish; end
      end
      g9 = o9[23:0]; ga = oa[23:0]; gb = ob[23:0];
      $display("%-12s K=%0d exp=%0d | v9=%0d(%0dcy) %s | v10a=%0d(%0dcy) %s | v10b=%0d(%0dcy) %s",
        name, K, exp,
        $signed(g9), cy9, ($signed(g9)===exp) ? "PASS":"FAIL",
        $signed(ga), cya, ($signed(ga)===exp) ? "PASS":"FAIL",
        $signed(gb), cyb, ($signed(gb)===exp) ? "PASS":"FAIL");
    end
  endtask
  initial begin
    for (i=0; i<64; i=i+1) begin amem[i]=4'd1; wmem[i]=4'd1; end
    run_case(4,  "ones");
    run_case(16, "ones-chunk");
    for (i=0; i<64; i=i+1) begin amem[i]=4'b1000; wmem[i]=4'b1000; end
    run_case(32, "adversarial");
    for (i=0; i<64; i=i+1) begin amem[i]=(i*7+3); wmem[i]=(i*5+1); end
    run_case(37, "random");
    $finish;
  end
endmodule
