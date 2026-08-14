`timescale 1ns/1ps
// SRAM-streaming golden RMSNorm plus residual.  It reads O one 64-bit word at
// a time twice and never materializes the 128-byte vector in flip-flops.
module streaming_norm(
 input wire clk,input wire rst_n,input wire start,
 output reg ivec_rd_en,output reg [3:0] ivec_rd_addr,input wire [63:0] ivec_rd_data,input wire ivec_rd_valid,
 output reg act_rd_en,output reg [8:0] act_rd_addr,input wire [127:0] act_rd_data,input wire act_rd_valid,
 output reg act_wr_en,output reg [8:0] act_wr_addr,output reg [127:0] act_wr_data,
 output reg done
);
 localparam [20:0] IDLE=(21'd1<<0),ACC_REQ=(21'd1<<1),ACC_WAIT=(21'd1<<2),MEAN=(21'd1<<3),GUESS=(21'd1<<4),NR=(21'd1<<5),
            LO_REQ=(21'd1<<6),LO_WAIT=(21'd1<<7),HI_REQ=(21'd1<<8),HI_WAIT=(21'd1<<9),X_REQ=(21'd1<<10),X_WAIT=(21'd1<<11),WRITE=(21'd1<<12),
            ACC_PAIR=(21'd1<<13),ACC_HALF=(21'd1<<14),ACC_COMMIT=(21'd1<<15),ADD_RESIDUAL=(21'd1<<16),NR_PARTIAL=(21'd1<<17),NR_UPDATE=(21'd1<<18),NR_FACTOR=(21'd1<<19),SCALE_SETUP=(21'd1<<20);
 reg [20:0] st; reg [3:0] word; reg [2:0] beat,nr;
 reg [20:0] sumsq; reg [13:0] mean;
 reg signed [8:0] r; reg signed [8:0] y2;
 reg [63:0] o_lo,o_hi; reg [127:0] pending_write,x_cache,scaled_cache;
 (* keep = "true" *) reg signed [8:0] scale_r[0:15];
 reg [15:0] sq0,sq1,sq2,sq3,sq4,sq5,sq6,sq7;
 reg [16:0] pair0,pair1,pair2,pair3;
 reg [17:0] half0,half1;
 integer i; reg signed [7:0] x,o; reg [15:0] sq; reg [17:0] word_sum;
 reg signed [22:0] xy2,factor,next_y,scaled; reg signed [13:0] factor_q;
 reg [15:0] xy_lo_q,xy_hi_q; reg signed [16:0] nr_lo_q; reg signed [15:0] nr_hi_q; reg signed [8:0] residual_sum;
 function signed [7:0] sat8; input signed [11:0] z; begin
  if(z>127) sat8=127; else if(z<-128) sat8=-128; else sat8=z[7:0];
 end endfunction
 function signed [7:0] satadd8; input signed [7:0] a; input signed [7:0] b; reg signed [8:0] z; begin
  z=a+b; if(z>127) satadd8=127; else if(z<-128) satadd8=-128; else satadd8=z[7:0];
 end endfunction
 always @* begin
  ivec_rd_en=0; ivec_rd_addr=0; act_rd_en=0; act_rd_addr=0;
  act_wr_en=0; act_wr_addr=beat; act_wr_data=pending_write;
  case(st)
   ACC_REQ: begin ivec_rd_en=1; ivec_rd_addr=word; end
   LO_REQ: begin ivec_rd_en=1; ivec_rd_addr={beat,1'b0}; end
   HI_REQ: begin ivec_rd_en=1; ivec_rd_addr={beat,1'b1}; end
   X_REQ: begin act_rd_en=1; act_rd_addr=beat; end
   WRITE: begin act_wr_en=1; act_wr_addr=beat; end
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin st<=IDLE; done<=0; sumsq<=0; word<=0; beat<=0; nr<=0; mean<=0; r<=0; y2<=0; o_lo<=0; o_hi<=0; pending_write<=0; end
  else begin
   done<=0;
   case(st)
    IDLE: if(start) begin sumsq<=0; word<=0; st<=ACC_REQ; end
    ACC_REQ: st<=ACC_WAIT;
    ACC_WAIT: if(ivec_rd_valid) begin
     sq0 <= $signed(ivec_rd_data[7:0])*$signed(ivec_rd_data[7:0]);
     sq1 <= $signed(ivec_rd_data[15:8])*$signed(ivec_rd_data[15:8]);
     sq2 <= $signed(ivec_rd_data[23:16])*$signed(ivec_rd_data[23:16]);
     sq3 <= $signed(ivec_rd_data[31:24])*$signed(ivec_rd_data[31:24]);
     sq4 <= $signed(ivec_rd_data[39:32])*$signed(ivec_rd_data[39:32]);
     sq5 <= $signed(ivec_rd_data[47:40])*$signed(ivec_rd_data[47:40]);
     sq6 <= $signed(ivec_rd_data[55:48])*$signed(ivec_rd_data[55:48]);
     sq7 <= $signed(ivec_rd_data[63:56])*$signed(ivec_rd_data[63:56]);
     st<=ACC_PAIR;
    end
    ACC_PAIR: begin pair0<=sq0+sq1;pair1<=sq2+sq3;pair2<=sq4+sq5;pair3<=sq6+sq7;st<=ACC_HALF;end
    ACC_HALF: begin half0<=pair0+pair1;half1<=pair2+pair3;st<=ACC_COMMIT;end
    ACC_COMMIT: begin
     sumsq<=sumsq+half0+half1;
     if(word==15) st<=MEAN; else begin word<=word+1'b1; st<=ACC_REQ; end
    end
    MEAN: begin mean<=(sumsq>>7)<1?1:(sumsq>>7); st<=GUESS; end
    GUESS: begin
     if(mean<16) r<=128; else if(mean<256) r<=64; else if(mean<4096) r<=16; else r<=4;
     nr<=0; st<=NR;
    end
    NR: begin
     if(!nr[0]) begin y2<=($signed(r)*$signed(r))>>>8; nr<=nr+1'b1; end
     else begin
      xy_lo_q<=$unsigned(y2)*$unsigned({1'b0,mean[6:0]});
      xy_hi_q<=$unsigned(y2)*$unsigned({1'b0,mean[13:7]});
      st<=NR_FACTOR;
     end
    end
    NR_FACTOR: begin
     xy2=(($unsigned(xy_hi_q)*128)+$unsigned(xy_lo_q))>>8;
     factor_q<=(384-xy2)>>>1;
     st<=NR_PARTIAL;
    end
    NR_PARTIAL: begin
     nr_lo_q<=$signed(r)*$signed({1'b0,factor_q[6:0]});
     nr_hi_q<=$signed(r)*$signed(factor_q[13:7]);
     st<=NR_UPDATE;
    end
    NR_UPDATE: begin
     next_y=$signed(nr_hi_q)+($signed(nr_lo_q)>>>7);
     if(next_y<1) r<=1; else if(next_y>255) r<=255; else r<=next_y[8:0];
     if(nr==5) st<=SCALE_SETUP; else begin nr<=nr+1'b1;st<=NR;end
    end
    SCALE_SETUP: begin for(i=0;i<16;i=i+1)scale_r[i]<=r;beat<=0;st<=LO_REQ;end
    LO_REQ: st<=LO_WAIT;
    LO_WAIT: if(ivec_rd_valid) begin o_lo<=ivec_rd_data; st<=HI_REQ; end
    HI_REQ: st<=HI_WAIT;
    HI_WAIT: if(ivec_rd_valid) begin o_hi<=ivec_rd_data; st<=X_REQ; end
    X_REQ: st<=X_WAIT;
    X_WAIT: if(act_rd_valid) begin
     x_cache<=act_rd_data;
     for(i=0;i<16;i=i+1) begin
      if(i<8) o=$signed(o_lo[i*8 +: 8]); else o=$signed(o_hi[(i-8)*8 +: 8]);
      scaled=($signed(o)*$signed(scale_r[i]))>>>4;
      scaled_cache[i*8 +: 8] <= sat8(scaled);
     end
     st<=ADD_RESIDUAL;
    end
    ADD_RESIDUAL: begin
     for(i=0;i<16;i=i+1) pending_write[i*8 +: 8] <= satadd8($signed(x_cache[i*8 +: 8]),$signed(scaled_cache[i*8 +: 8]));
     st<=WRITE;
    end
    WRITE: if(beat==7) begin done<=1; st<=IDLE; end else begin beat<=beat+1'b1; st<=LO_REQ; end
   endcase
  end
 end
endmodule
