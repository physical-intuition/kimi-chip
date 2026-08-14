`timescale 1ns/1ps
module conv_unit(
 input wire clk,input wire rst_n,input wire valid,
 input wire [127:0] x,input wire [511:0] alpha_w,input wire [511:0] beta_w,
 output reg out_valid,output reg [127:0] alpha,output reg [127:0] beta
);
 integer i,t; reg signed [7:0] xv,aw,bw; reg signed [23:0] sa,sb;
 reg signed [23:0] qa,qb; reg signed [7:0] rawa,rawb;
 function signed [7:0] satq; input signed [23:0] z; reg signed [23:0] s; begin
  s=z>>>8; if(s>127)satq=127;else if(s< -128)satq=-128;else satq=s[7:0];
 end endfunction
 function [7:0] sigmoid;input signed [7:0] z;reg signed [15:0] u;begin
  if(z< -64)sigmoid=0;else if(z>64)sigmoid=127;else begin u=($signed(z)+64)*127;sigmoid=u/128;end
 end endfunction
 function signed [7:0] tanh_p;input signed [7:0] z;reg signed [8:0] d;begin
  if(z< -64)tanh_p=-127;else if(z>64)tanh_p=127;else begin d=z*2;tanh_p=d[7:0];end
 end endfunction
 always @(posedge clk) begin
  if(!rst_n)begin out_valid<=0;alpha<=0;beta<=0;end else begin
   out_valid<=valid;
   if(valid)for(i=0;i<16;i=i+1)begin
    xv=$signed(x[i*8 +:8]);sa=0;sb=0;
    for(t=0;t<4;t=t+1)begin
     aw=$signed(alpha_w[(i*4+t)*8 +:8]);bw=$signed(beta_w[(i*4+t)*8 +:8]);
     sa=sa+xv*aw;sb=sb+xv*bw;
    end
    rawa=satq(sa);rawb=satq(sb);alpha[i*8 +:8]<=sigmoid(rawa);beta[i*8 +:8]<=tanh_p(rawb);
   end
  end
 end
endmodule
