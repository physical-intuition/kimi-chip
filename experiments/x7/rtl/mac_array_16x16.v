`timescale 1ns/1ps
// 32 products per beat with a balanced five-level reduction tree.
module mac_array_16x16(
 input wire clk,input wire rst_n,input wire clear,input wire valid,input wire last,
 input wire [255:0] weights,input wire [255:0] activations,
 output reg result_valid,output reg signed [23:0] result
);
 wire signed [15:0] p[0:31];wire signed [16:0]s1[0:15];wire signed[17:0]s2[0:7];
 reg signed[17:0]s2q[0:7];reg valid_q,clear_q,last_q;
 wire signed[18:0]s3[0:3];wire signed[19:0]s4[0:1];wire signed[20:0]sum;
 genvar g;generate
  for(g=0;g<32;g=g+1)assign p[g]=$signed(weights[g*8+:8])*$signed(activations[g*8+:8]);
  for(g=0;g<16;g=g+1)assign s1[g]=$signed(p[2*g])+$signed(p[2*g+1]);
  for(g=0;g<8;g=g+1)assign s2[g]=$signed(s1[2*g])+$signed(s1[2*g+1]);
  for(g=0;g<4;g=g+1)assign s3[g]=$signed(s2q[2*g])+$signed(s2q[2*g+1]);
  for(g=0;g<2;g=g+1)assign s4[g]=$signed(s3[2*g])+$signed(s3[2*g+1]);
 endgenerate
 assign sum=$signed(s4[0])+$signed(s4[1]);
 reg signed[24:0]total;
 function signed[23:0]sat24;input signed[24:0]x;begin if(x>25'sd8388607)sat24=24'sh7fffff;else if(x< -25'sd8388608)sat24=24'sh800000;else sat24=x[23:0];end endfunction
 integer j;
 always@(posedge clk)begin
  if(!rst_n)begin result<=0;result_valid<=0;valid_q<=0;clear_q<=0;last_q<=0;for(j=0;j<8;j=j+1)s2q[j]<=0;end
  else begin
   result_valid<=0;valid_q<=valid;clear_q<=clear;last_q<=last;
   if(valid)for(j=0;j<8;j=j+1)s2q[j]<=s2[j];
   if(clear&&!valid_q)result<=0;
   if(valid_q)begin total=(clear_q?25'sd0:$signed({result[23],result}))+{{4{sum[20]}},sum};result<=sat24(total);if(last_q)result_valid<=1;end
  end
 end
endmodule
