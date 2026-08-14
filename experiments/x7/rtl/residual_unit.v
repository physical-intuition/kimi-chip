`timescale 1ns/1ps
module residual_unit(input wire [1023:0] main,input wire [1023:0] skip,output reg [1023:0] out);
 integer i;reg signed [8:0] z;
 function signed [7:0] sat8;input signed [8:0] x;begin if(x>127)sat8=127;else if(x< -128)sat8=-128;else sat8=x[7:0];end endfunction
 always @* for(i=0;i<128;i=i+1)begin z=$signed(main[i*8 +:8])+$signed(skip[i*8 +:8]);out[i*8 +:8]=sat8(z);end
endmodule
