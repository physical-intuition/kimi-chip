`timescale 1ns/1ps
// Y4 four-stage serial gate unit. Products, pair reductions, final reductions,
// and quantize/clamp each terminate at a register for additional timing margin.
module conv_unit_serial(
 input wire clk,input wire rst_n,input wire valid,input wire signed [7:0] x,
 input wire [31:0] alpha_w,input wire [31:0] beta_w,
 output reg out_valid,output reg [7:0] alpha,output reg signed [7:0] beta
);
 reg v0,v1,v2;
 reg signed [15:0] ap0,ap1,ap2,ap3,bp0,bp1,bp2,bp3;
 reg signed [16:0] aa0,aa1,bb0,bb1;
 reg signed [17:0] sa,sb;
 reg signed [7:0] ra,rb;
 function signed [7:0] satq;
  input signed [17:0] z;
  reg signed [9:0] shifted;
  begin
   shifted=z>>>8;
   if(shifted>127) satq=127;
   else if(shifted < -128) satq=-128;
   else satq=shifted[7:0];
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   v0<=0;v1<=0;v2<=0;out_valid<=0;alpha<=0;beta<=0;
  end else begin
   v0<=valid;v1<=v0;v2<=v1;out_valid<=v2;
   if(valid) begin
    ap0<=x*$signed(alpha_w[7:0]);ap1<=x*$signed(alpha_w[15:8]);
    ap2<=x*$signed(alpha_w[23:16]);ap3<=x*$signed(alpha_w[31:24]);
    bp0<=x*$signed(beta_w[7:0]);bp1<=x*$signed(beta_w[15:8]);
    bp2<=x*$signed(beta_w[23:16]);bp3<=x*$signed(beta_w[31:24]);
   end
   if(v0) begin
    aa0<=ap0+ap1;aa1<=ap2+ap3;bb0<=bp0+bp1;bb1<=bp2+bp3;
   end
   if(v1) begin sa<=aa0+aa1;sb<=bb0+bb1;end
   if(v2) begin
    ra=satq(sa);rb=satq(sb);
    if(ra<=-64)alpha<=0;else if(ra>63)alpha<=127;else alpha<=ra+8'sd63;
    if(rb < -64)beta<=-127;else if(rb>64)beta<=127;else beta<=rb<<<1;
   end
  end
 end
endmodule
