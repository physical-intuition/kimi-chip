`timescale 1ns/1ps
// Sixteen-lane RMSNorm. The reciprocal-root is a 32-entry leading-one LUT,
// registered through the eight-cycle refinement contract. It deliberately
// avoids an inferred divider/isqrt cone in the physical implementation.
module norm_unit (
 input wire clk,input wire rst_n,input wire start,input wire in_valid,output wire in_ready,
 input wire [383:0] in_data,output reg out_valid,input wire out_ready,output reg [127:0] out_data,output reg done
);
 localparam IDLE=2'd0,COLLECT=2'd1,REFINE=2'd2,EMIT=2'd3;
 reg [1:0] state; reg [3:0] beat_count; reg [2:0] refine_count;
 reg [63:0] sum_squares,mean_square; reg signed [23:0] samples[0:127]; reg [23:0] scale_q14;
 integer lane; reg signed [23:0] sample_temp; reg [47:0] square_temp; reg [63:0] beat_square_sum; reg signed [47:0] scaled_temp;
 assign in_ready=(state==COLLECT);
 function signed [7:0] sat8; input signed [47:0] value; begin
   if(value>48'sd127) sat8=8'sd127; else if(value < -48'sd128) sat8=-8'sd128; else sat8=value[7:0];
 end endfunction
 // Q14 reciprocal sqrt for lower edge of leading-one bins. Conservative and
 // monotonic; a macro/LUT implementation replaces Y3's exact combinational math.
 function [23:0] rsqrt_lut_q14; input [63:0] value; integer i; reg [5:0] msb; begin
   msb=0; for(i=0;i<64;i=i+1) if(value[i]) msb=i;
   case(msb)
    0:rsqrt_lut_q14=16384; 1:rsqrt_lut_q14=11585; 2:rsqrt_lut_q14=8192; 3:rsqrt_lut_q14=5793;
    4:rsqrt_lut_q14=4096; 5:rsqrt_lut_q14=2896; 6:rsqrt_lut_q14=2048; 7:rsqrt_lut_q14=1448;
    8:rsqrt_lut_q14=1024; 9:rsqrt_lut_q14=724; 10:rsqrt_lut_q14=512; 11:rsqrt_lut_q14=362;
    12:rsqrt_lut_q14=256; 13:rsqrt_lut_q14=181; 14:rsqrt_lut_q14=128; 15:rsqrt_lut_q14=91;
    16:rsqrt_lut_q14=64; 17:rsqrt_lut_q14=45; 18:rsqrt_lut_q14=32; 19:rsqrt_lut_q14=23;
    20:rsqrt_lut_q14=16; 21:rsqrt_lut_q14=11; 22:rsqrt_lut_q14=8; 23:rsqrt_lut_q14=6;
    24:rsqrt_lut_q14=4; 25:rsqrt_lut_q14=3; 26:rsqrt_lut_q14=2; 27:rsqrt_lut_q14=2;
    default:rsqrt_lut_q14=1;
   endcase
 end endfunction
 always @(posedge clk) begin
  if(!rst_n) begin state<=IDLE;beat_count<=0;refine_count<=0;sum_squares<=0;mean_square<=0;scale_q14<=0;out_valid<=0;out_data<=0;done<=0; for(lane=0;lane<128;lane=lane+1)samples[lane]<=0; end
  else begin
   done<=0; if(out_valid&&out_ready)out_valid<=0;
   case(state)
    IDLE:if(start)begin state<=COLLECT;beat_count<=0;sum_squares<=0;out_valid<=0;end
    COLLECT:if(in_valid&&in_ready)begin beat_square_sum=0;for(lane=0;lane<16;lane=lane+1)begin sample_temp=in_data[lane*24+:24];samples[beat_count*16+lane]<=sample_temp;square_temp=sample_temp*sample_temp;beat_square_sum=beat_square_sum+{16'd0,square_temp};end sum_squares<=sum_squares+beat_square_sum;if(beat_count==7)begin mean_square<=(sum_squares+beat_square_sum)>>7;refine_count<=0;state<=REFINE;end else beat_count<=beat_count+1'b1;end
    REFINE:begin if(refine_count==0)scale_q14<=rsqrt_lut_q14(mean_square+1);if(refine_count==7)begin beat_count<=0;state<=EMIT;end else refine_count<=refine_count+1'b1;end
    EMIT:if(!out_valid||out_ready)begin for(lane=0;lane<16;lane=lane+1)begin scaled_temp=$signed(samples[beat_count*16+lane])*$signed({1'b0,scale_q14});out_data[lane*8+:8]<=sat8(scaled_temp>>>14);end out_valid<=1;if(beat_count==7)begin state<=IDLE;done<=1;end else beat_count<=beat_count+1'b1;end
   endcase
  end
 end
endmodule
