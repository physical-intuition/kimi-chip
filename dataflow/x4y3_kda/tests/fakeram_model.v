module fakeram45_512x64(
 input clk, ce_in, we_in, input [8:0] addr_in,
 input [63:0] wd_in,w_mask_in, output reg [63:0] rd_out);
 reg [63:0] mem[0:511];
 always @(posedge clk) if(ce_in) begin
   if(we_in) mem[addr_in] <= (wd_in & w_mask_in) | (mem[addr_in] & ~w_mask_in);
   rd_out <= mem[addr_in];
 end
endmodule
