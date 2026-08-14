`timescale 1ns/1ps
// Y3 pipelined eight-lane state engine. Wide beta*k*d products are decomposed
// into signed 8x8/9x8 partial products, so every stage has at most one small
// multiply or one add/saturate operation.
module state_word_engine(
 input wire clk,input wire rst_n,input wire valid,input wire pass2,
 input wire signed [7:0] alpha,input wire signed [7:0] beta,
 input wire signed [7:0] k,input wire signed [7:0] q,
 input wire [63:0] state_slice,input wire [63:0] diff_slice,
 output reg [63:0] updated_slice,
 output reg signed [23:0] term0,term1,term2,term3,term4,term5,term6,term7,
 output reg out_valid
);
 integer i;
 reg v0,v1,v2,v3,v4;
 reg p0,p1,p2,p3;
 reg [63:0] s0,d0,s1,d1,s2,s3,n2,n3,n4;
 (* keep = "true" *) reg signed [7:0] alpha0[0:7],beta0[0:7],k0[0:7],q0[0:7];
 (* keep = "true" *) reg signed [7:0] k1[0:7],q1[0:7],k2[0:7],q2[0:7],k3[0:7],q3[0:7],coef4[0:7];
 reg signed [15:0] sa1[0:7];
 reg signed [15:0] bk1[0:7];
 reg signed [16:0] bkd_lo2[0:7];
 reg signed [15:0] bkd_hi2[0:7];
 reg signed [23:0] bkd3[0:7];
 function signed [7:0] sat9;
  input signed [8:0] z;
  begin if(z>127) sat9=127; else if(z < -128) sat9=-128; else sat9=z[7:0]; end
 endfunction
 function signed [7:0] sat10;
  input signed [9:0] z;
  begin if(z>127) sat10=127; else if(z < -128) sat10=-128; else sat10=z[7:0]; end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   v0<=0;v1<=0;v2<=0;v3<=0;v4<=0;out_valid<=0;updated_slice<=0;
   term0<=0;term1<=0;term2<=0;term3<=0;term4<=0;term5<=0;term6<=0;term7<=0;
  end else begin
   v0<=valid;v1<=v0;v2<=v1;v3<=v2;v4<=v3;out_valid<=v4;
   if(valid) begin
    p0<=pass2;s0<=state_slice;d0<=diff_slice;
    for(i=0;i<8;i=i+1) begin alpha0[i]<=alpha;beta0[i]<=beta;k0[i]<=k;q0[i]<=q;end
   end
   if(v0) begin
    p1<=p0;s1<=s0;d1<=d0;
    for(i=0;i<8;i=i+1) begin
     k1[i]<=k0[i];q1[i]<=q0[i];
     sa1[i]<=$signed(s0[i*8 +:8])*$signed(alpha0[i]);
     bk1[i]<=$signed(beta0[i])*$signed(k0[i]);
    end
   end
   if(v1) begin
    p2<=p1;s2<=s1;
    for(i=0;i<8;i=i+1) begin
     k2[i]<=k1[i];q2[i]<=q1[i];
     n2[i*8 +:8]<=sat9($signed(sa1[i])>>>7);
     bkd_lo2[i]<=$signed({1'b0,bk1[i][7:0]})*$signed(d1[i*8 +:8]);
     bkd_hi2[i]<=$signed(bk1[i][15:8])*$signed(d1[i*8 +:8]);
    end
   end
   if(v2) begin
    p3<=p2;s3<=s2;n3<=n2;
    for(i=0;i<8;i=i+1) begin k3[i]<=k2[i];q3[i]<=q2[i];bkd3[i]<=($signed(bkd_hi2[i])<<<8)+$signed(bkd_lo2[i]);end
   end
   if(v3) begin
    for(i=0;i<8;i=i+1) begin
     coef4[i]<=p3?q3[i]:k3[i];
     if(p3)n4[i*8 +:8]<=sat10($signed(s3[i*8 +:8])+($signed(bkd3[i])>>>14));
     else n4[i*8 +:8]<=n3[i*8 +:8];
    end
   end
   if(v4) begin
    updated_slice<=n4;
    term0<=$signed(n4[7:0])*$signed(coef4[0]);term1<=$signed(n4[15:8])*$signed(coef4[1]);
    term2<=$signed(n4[23:16])*$signed(coef4[2]);term3<=$signed(n4[31:24])*$signed(coef4[3]);
    term4<=$signed(n4[39:32])*$signed(coef4[4]);term5<=$signed(n4[47:40])*$signed(coef4[5]);
    term6<=$signed(n4[55:48])*$signed(coef4[6]);term7<=$signed(n4[63:56])*$signed(coef4[7]);
   end
  end
 end
endmodule
