`timescale 1ns/1ps
// Simulation model for the Nangate45 hard SRAM. During logic synthesis this
// module is treated as a black box; the real macro liberty is kept separate.
(* blackbox *) module fakeram45_128x256 (
  input wire clk, input wire ce_in, input wire we_in,
  input wire [6:0] addr_in, input wire [255:0] wd_in,
  input wire [255:0] w_mask_in, output reg [255:0] rd_out
);
`ifndef SYNTHESIS
  reg [255:0] mem [0:127];
  integer i;
  always @(posedge clk) if (ce_in) begin
    if (we_in) for (i=0;i<256;i=i+1) if (w_mask_in[i]) mem[addr_in][i] <= wd_in[i];
    rd_out <= mem[addr_in];
  end
`endif
endmodule
