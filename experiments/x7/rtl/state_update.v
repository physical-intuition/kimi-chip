`timescale 1ns/1ps
// Combinational 32-element slice used by both 512-cycle state scans.
module state_update(
 input wire pass2,input wire [255:0] state_in,input wire signed [7:0] alpha,
 input wire signed [7:0] beta,input wire signed [7:0] k,input wire signed [7:0] q,
 input wire [255:0] diff,
 output reg [255:0] state_out,output reg [767:0] reduction_terms
);
 integer i;reg signed [7:0] s,d,sp,sn;reg signed [15:0] p1,bk,term16;
 reg signed [23:0] p3,add,term;
 function signed [7:0] sat8;input signed [31:0] z;begin
  if(z>127)sat8=127;else if(z< -128)sat8=-128;else sat8=z[7:0];
 end endfunction
 always @* begin
  state_out=0;reduction_terms=0;bk=$signed(beta)*$signed(k);
  for(i=0;i<32;i=i+1)begin
   s=$signed(state_in[i*8 +:8]);d=$signed(diff[i*8 +:8]);
   if(!pass2)begin
    p1=s*alpha;sp=sat8(p1>>>7);state_out[i*8 +:8]=sp;
    term16=$signed(sp)*$signed(k);term={{8{term16[15]}},term16};reduction_terms[i*24 +:24]=term;
   end else begin
    p3=$signed(bk)*$signed(d);add=$signed(s)+(p3>>>14);
    sn=sat8(add);state_out[i*8 +:8]=sn;
    term16=$signed(sn)*$signed(q);term={{8{term16[15]}},term16};reduction_terms[i*24 +:24]=term;
   end
  end
 end
endmodule
