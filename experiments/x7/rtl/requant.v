`timescale 1ns/1ps
module requant(input wire signed [23:0] in_data,output reg signed [7:0] out_data);
 reg signed [23:0] shifted;
 always @* begin
  shifted=in_data>>>8;
  if(shifted>24'sd127) out_data=8'sd127;
  else if(shifted< -24'sd128) out_data=-8'sd128;
  else out_data=shifted[7:0];
 end
endmodule
