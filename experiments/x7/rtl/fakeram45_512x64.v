`timescale 1ns/1ps
// Simulation model. Synthesis reads this file with read_verilog -lib, so the
// array is retained as an external hard macro rather than inferred logic.
module fakeram45_512x64 (
  input clk, input ce_in, input we_in, input [8:0] addr_in,
  input [63:0] wd_in, output reg [63:0] rd_out
);
  reg [63:0] mem [0:511];
  always @(posedge clk) begin
    if (ce_in) begin
      if (we_in) mem[addr_in] <= wd_in;
      rd_out <= mem[addr_in];
    end
  end
endmodule
