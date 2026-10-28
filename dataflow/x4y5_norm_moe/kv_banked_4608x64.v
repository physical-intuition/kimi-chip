// X4Y4 MLA KV cache: nine physical 512x64 macros = 64 positions x 72 words
// (kc 64 + kr 16 + v 64 Q16.16 values, two per word). Bank select follows
// the synchronous read latency, as in kv_banked_2048x64.
module kv_banked_4608x64 (
 input wire clk, ce_in, we_in,
 input wire [12:0] addr_in,
 input wire [63:0] wd_in, w_mask_in,
 output wire [63:0] rd_out
);
 reg [3:0] read_bank;
 wire [63:0] rdata [0:8];
 always @(posedge clk) if (ce_in) read_bank <= addr_in[12:9];
 genvar b;
 generate for (b=0;b<9;b=b+1) begin: banks
   fakeram45_512x64 ram(
     .clk(clk), .ce_in(ce_in && (addr_in[12:9] == b)),
     .we_in(we_in), .addr_in(addr_in[8:0]),
     .wd_in(wd_in), .w_mask_in(w_mask_in), .rd_out(rdata[b]));
 end endgenerate
 assign rd_out = rdata[read_bank];
endmodule
