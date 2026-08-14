`timescale 1ns/1ps
module conv_unit_serial(input wire clk,input wire rst_n,input wire valid,input wire signed[7:0]x,input wire[31:0]alpha_w,input wire[31:0]beta_w,output reg out_valid,output reg[7:0]alpha,output reg signed[7:0]beta);
 wire signed[15:0]ap0=x*$signed(alpha_w[7:0]),ap1=x*$signed(alpha_w[15:8]),ap2=x*$signed(alpha_w[23:16]),ap3=x*$signed(alpha_w[31:24]);
 wire signed[15:0]bp0=x*$signed(beta_w[7:0]),bp1=x*$signed(beta_w[15:8]),bp2=x*$signed(beta_w[23:16]),bp3=x*$signed(beta_w[31:24]);
 wire signed[16:0]aa0=ap0+ap1,aa1=ap2+ap3,bb0=bp0+bp1,bb1=bp2+bp3;
 wire signed[17:0]sa=aa0+aa1,sb=bb0+bb1;reg signed[17:0]s;reg signed[7:0]ra,rb;reg signed[8:0]d;
 function signed[7:0]satq;input signed[17:0]z;begin s=z>>>8;if(s>127)satq=127;else if(s< -128)satq=-128;else satq=s[7:0];end endfunction
 always@(posedge clk)begin if(!rst_n)begin out_valid<=0;alpha<=0;beta<=0;end else begin out_valid<=valid;if(valid)begin ra=satq(sa);rb=satq(sb);if(ra< -64)alpha<=0;else if(ra>63)alpha<=127;else if(ra== -64)alpha<=0;else alpha<=ra+8'sd63;if(rb< -64)beta<=-127;else if(rb>64)beta<=127;else begin d=rb<<<1;beta<=d[7:0];end end end end
endmodule
