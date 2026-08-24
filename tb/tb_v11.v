`timescale 1ns/1ps
module tb_v11;
  reg clk=0, rst_n=0, start=0;
  reg [15:0] k_dim;
  reg [3:0] amem [0:63];
  reg [3:0] wmem [0:63];
  always #1 clk = ~clk;
  wire cw, ca, dn; wire [15:0] aw, aa; reg [63:0] rw, ra;
  wire [256*24-1:0] o;
  always @(posedge clk) begin
    if (cw) rw <= {16{wmem[aw[5:0]]}};
    if (ca) ra <= {16{amem[aa[5:0]]}};
  end
  compute_core_v11 dut(.clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
    .wgt_cs(cw), .wgt_addr(aw), .wgt_rdata(rw),
    .act_cs(ca), .act_addr(aa), .act_rdata(ra), .acc_out(o), .done(dn));
  integer i, exp, t0, cyc;
  task run_case(input [15:0] K, input do_rst, input [127:0] name);
    begin
      exp = 0; for (i=0; i<K; i=i+1) exp = exp + $signed(amem[i]) * $signed(wmem[i]);
      if (do_rst) begin rst_n=0; #4 rst_n=1; end
      k_dim = K; @(negedge clk); start=1; @(negedge clk); start=0; t0=$time; cyc=0;
      while (!dn) begin #2; cyc=cyc+1; if ($time-t0>8000) begin $display("TIMEOUT %0s",name); $finish; end end
      $display("%-12s K=%0d acc=%0d exp=%0d %s (%0dcy)", name, K,
        $signed(o[23:0]), exp, ($signed(o[23:0])===exp)?"PASS":"FAIL", cyc);
      #6;
    end
  endtask
  initial begin
    for (i=0; i<64; i=i+1) begin amem[i]=4'd1; wmem[i]=4'd1; end
    run_case(4, 1, "ones");
    run_case(16, 0, "chunk-noreset");
    for (i=0; i<64; i=i+1) begin amem[i]=4'b1000; wmem[i]=4'b1000; end
    run_case(32, 0, "adversarial");
    for (i=0; i<64; i=i+1) begin amem[i]=(i*7+3); wmem[i]=(i*5+1); end
    run_case(37, 0, "random");
    run_case(1, 0, "K1");
    $finish;
  end
endmodule
