`timescale 1ns/1ps
// 24-cycle golden RMSNorm. Samples/results are narrow addressed files, avoiding
// variable writes into 1024-bit packed registers.
module norm_unit(input wire clk,input wire rst_n,input wire start,input wire[1023:0]x,output reg done,output wire[1023:0]y_out);
 localparam IDLE=0,ACC=1,MEAN=2,GUESS=3,NR=4,SCALE=5;reg[2:0]state;reg[3:0]beat;reg[2:0]nr_cycle;
 reg[20:0]sum_sq;reg[13:0]mean_sq;reg signed[8:0]rsqrt;reg signed[16:0]y2;
 reg signed[7:0]sample[0:127],result[0:127];integer i;reg signed[7:0]v;reg[15:0]sq;reg[17:0]beat_sum;reg signed[22:0]xy2,factor,next_y,scaled;
 genvar g;generate for(g=0;g<128;g=g+1)begin:outg assign y_out[g*8+:8]=result[g];end endgenerate
 function signed[7:0]sat8;input signed[22:0]z;begin if(z>127)sat8=127;else if(z< -128)sat8=-128;else sat8=z[7:0];end endfunction
 always@(posedge clk)begin
  if(!rst_n)begin state<=IDLE;done<=0;sum_sq<=0;mean_sq<=0;rsqrt<=0;y2<=0;beat<=0;nr_cycle<=0;end
  else begin done<=0;case(state)
   IDLE:if(start)begin for(i=0;i<128;i=i+1)sample[i]<=x[i*8+:8];sum_sq<=0;beat<=0;state<=ACC;end
   ACC:begin beat_sum=0;for(i=0;i<16;i=i+1)begin v=sample[beat*16+i];sq=v*v;beat_sum=beat_sum+sq;end sum_sq<=sum_sq+beat_sum;if(beat==7)begin beat<=0;state<=MEAN;end else beat<=beat+1'b1;end
   MEAN:begin mean_sq<=(sum_sq>>7)<1?1:(sum_sq>>7);state<=GUESS;end
   GUESS:begin if(mean_sq<16)rsqrt<=128;else if(mean_sq<256)rsqrt<=64;else if(mean_sq<4096)rsqrt<=16;else rsqrt<=4;nr_cycle<=0;state<=NR;end
   NR:begin if(!nr_cycle[0])y2<=($signed(rsqrt)*$signed(rsqrt))>>>8;else begin xy2=($signed({1'b0,mean_sq})*$signed(y2))>>>8;factor=(384-xy2)>>>1;next_y=($signed(rsqrt)*factor)>>>7;if(next_y<1)rsqrt<=1;else if(next_y>255)rsqrt<=255;else rsqrt<=next_y[8:0];end if(nr_cycle==5)begin beat<=0;state<=SCALE;end else nr_cycle<=nr_cycle+1'b1;end
   SCALE:begin for(i=0;i<16;i=i+1)begin v=sample[beat*16+i];scaled=($signed(v)*$signed(rsqrt))>>>4;result[beat*16+i]<=sat8(scaled);end if(beat==7)begin state<=IDLE;done<=1;end else beat<=beat+1'b1;end
  endcase end
 end
endmodule
