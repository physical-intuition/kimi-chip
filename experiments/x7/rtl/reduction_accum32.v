`timescale 1ns/1ps
module reduction_accum32(input wire clk,input wire rst_n,input wire clear,input wire enable,input wire [767:0] terms,output reg [767:0] sums);
 integer i;reg signed[24:0] z;
 function signed[23:0] sat;input signed[24:0] x;begin if(x>8388607)sat=24'sh7fffff;else if(x< -8388608)sat=24'sh800000;else sat=x[23:0];end endfunction
 always@(posedge clk)begin
  if(!rst_n||clear)sums<=0;
  else if(enable)for(i=0;i<32;i=i+1)begin z=$signed({sums[i*24+23],sums[i*24 +:24]})+$signed({terms[i*24+23],terms[i*24 +:24]});sums[i*24 +:24]<=sat(z);end
 end
endmodule
