`timescale 1ns/1ps
// Y4 deeply pipelined 32-product MAC. Each reduction level terminates at a
// register, leaving only one adder level or the final accumulate/saturate per stage.
module mac_array_16x16(
 input wire clk,input wire rst_n,input wire clear,input wire valid,input wire last,
 input wire [255:0] weights,input wire [255:0] activations,
 output reg result_valid,output reg signed [23:0] result
);
 reg signed [15:0] p0[0:31];
 reg signed [16:0] s1[0:15];
 reg signed [17:0] s2[0:7];
 reg signed [18:0] s3[0:3];
 reg signed [19:0] s4[0:1];
 reg signed [20:0] sum_q;
 reg v0,v1,v2,v3,v4,v5;
 reg c0,c1,c2,c3,c4,c5;
 reg l0,l1,l2,l3,l4,l5;
 wire signed [24:0] acc_sum=(c5?25'sd0:$signed({result[23],result}))+{{4{sum_q[20]}},sum_q};
 function signed [23:0] sat24;
  input signed [24:0] x;
  begin
   if(x>25'sd8388607)sat24=24'sh7fffff;
   else if(x < -25'sd8388608)sat24=24'sh800000;
   else sat24=x[23:0];
  end
 endfunction
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   result<=0;result_valid<=0;
   v0<=0;v1<=0;v2<=0;v3<=0;v4<=0;v5<=0;
   c0<=0;c1<=0;c2<=0;c3<=0;c4<=0;c5<=0;
   l0<=0;l1<=0;l2<=0;l3<=0;l4<=0;l5<=0;
  end else begin
   v0<=valid;v1<=v0;v2<=v1;v3<=v2;v4<=v3;v5<=v4;
   c0<=clear;c1<=c0;c2<=c1;c3<=c2;c4<=c3;c5<=c4;
   l0<=last;l1<=l0;l2<=l1;l3<=l2;l4<=l3;l5<=l4;
   result_valid<=v5&&l5;
   if(clear&&!valid)result<=0;
   if(valid)for(i=0;i<32;i=i+1)p0[i]<=$signed(weights[i*8+:8])*$signed(activations[i*8+:8]);
   if(v0)for(i=0;i<16;i=i+1)s1[i]<=$signed(p0[2*i])+$signed(p0[2*i+1]);
   if(v1)for(i=0;i<8;i=i+1)s2[i]<=$signed(s1[2*i])+$signed(s1[2*i+1]);
   if(v2)for(i=0;i<4;i=i+1)s3[i]<=$signed(s2[2*i])+$signed(s2[2*i+1]);
   if(v3)for(i=0;i<2;i=i+1)s4[i]<=$signed(s3[2*i])+$signed(s3[2*i+1]);
   if(v4)sum_q<=$signed(s4[0])+$signed(s4[1]);
   if(v5)result<=sat24(acc_sum);
  end
 end
endmodule
