`timescale 1ns/1ps
// Serialized, SRAM-owned KDA state update.  It keeps only one 256-bit state
// word, one 256-bit diff word, two vector words, and the 32 reusable sums.
module state_stream_controller(
 input wire clk,input wire rst_n,input wire start,input wire active_bank_in,
 output reg done,output reg active_bank_out,
 output reg state_rd_en,output reg state_rd_bank,output reg [8:0] state_rd_addr,
 input wire [255:0] state_rd_data,input wire state_rd_valid,
 output reg state_wr_en,output reg state_wr_bank,output reg [8:0] state_wr_addr,output reg [255:0] state_wr_data,
 output reg act_rd_en,output reg act_rd_bank,output reg [8:0] act_rd_addr,
 input wire [127:0] act_rd_data,input wire act_rd_valid,
 output reg act_wr_en,output reg act_wr_bank,output reg [8:0] act_wr_addr,output reg [127:0] act_wr_data,
 output reg ivec_rd_en,output reg [1:0] ivec_rd_vector_sel,output reg [3:0] ivec_rd_word_addr,
 input wire [63:0] ivec_rd_data,input wire ivec_rd_valid
);
 localparam [23:0] IDLE=24'h000001, P1_GATE=24'h000002, P1_K=24'h000004, P1_STATE=24'h000008,
            P1_GO=24'h000010, P1_WAIT=24'h000020, P1_COMMIT=24'h000040, P1_WRITE=24'h000080,
            P1_V=24'h000100, P1_DIFF=24'h000200, P2_D0=24'h000400, P2_D1=24'h000800,
            P2_GATE=24'h001000, P2_K=24'h002000, P2_Q=24'h004000, P2_STATE=24'h008000,
            P2_GO=24'h010000, P2_WAIT=24'h020000, P2_COMMIT=24'h040000, P2_WRITE=24'h080000,
            P2_Y=24'h100000, P1_DIFF_PREP=24'h200000, P2_Y_PREP=24'h400000, P1_DIFF_RQ=24'h800000;
 reg [23:0] fsm;
 reg [1:0] chunk, group;
 reg [6:0] row;
 reg diff_half;
 reg read_issued;
 reg [1:0] vword;
 reg [127:0] gate_cache;
 reg [63:0] k_cache,q_cache;
 reg [255:0] state_word,state_build,diff_cache,v_cache;
 reg [127:0] write_data_q,rq_data_q;
 reg signed [23:0] acc[0:31];
 integer i;

 wire eng_valid=(fsm==P1_GO)||(fsm==P2_GO);
 wire eng_out_valid; wire [63:0] eng_slice;
 wire signed [23:0] t0,t1,t2,t3,t4,t5,t6,t7;
 wire signed [7:0] alpha=$signed(gate_cache[row[2:0]*16 +: 8]);
 wire signed [7:0] beta =$signed(gate_cache[row[2:0]*16+8 +: 8]);
 wire signed [7:0] kval =$signed(k_cache[row[2:0]*8 +: 8]);
 wire signed [7:0] qval =$signed(q_cache[row[2:0]*8 +: 8]);
 reg [63:0] engine_state_slice,engine_diff_slice;
 always @* begin
  case(group)
   0: begin engine_state_slice=state_word[63:0]; engine_diff_slice=diff_cache[63:0]; end
   1: begin engine_state_slice=state_word[127:64]; engine_diff_slice=diff_cache[127:64]; end
   2: begin engine_state_slice=state_word[191:128]; engine_diff_slice=diff_cache[191:128]; end
   default: begin engine_state_slice=state_word[255:192]; engine_diff_slice=diff_cache[255:192]; end
  endcase
 end
 state_word_engine engine(.clk(clk),.rst_n(rst_n),.valid(eng_valid),.pass2(fsm==P2_GO),
  .alpha(alpha),.beta(beta),.k(kval),.q(qval),.state_slice(engine_state_slice),.diff_slice(engine_diff_slice),
  .updated_slice(eng_slice),.term0(t0),.term1(t1),.term2(t2),.term3(t3),.term4(t4),.term5(t5),.term6(t6),.term7(t7),.out_valid(eng_out_valid));
 function signed [7:0] rq8; input signed [23:0] a; reg signed [14:0] x; begin
  x=a>>>8; if(x>127)rq8=127; else if(x < -128)rq8=-128; else rq8=x[7:0];
 end endfunction
 function signed [7:0] make_diff8; input signed [7:0] v; input signed [7:0] u; reg signed [8:0] x; begin
  x=v-u; if(x>127)make_diff8=127; else if(x < -128)make_diff8=-128; else make_diff8=x[7:0];
 end endfunction

 always @* begin
  active_bank_out=active_bank_in;
  state_rd_en=0; state_rd_bank=0; state_rd_addr=0; state_wr_en=0; state_wr_bank=0; state_wr_addr=0; state_wr_data=state_build;
  act_rd_en=0; act_rd_bank=0; act_rd_addr=0; act_wr_en=0; act_wr_bank=0; act_wr_addr=0; act_wr_data=0;
  ivec_rd_en=0; ivec_rd_vector_sel=0; ivec_rd_word_addr=0;
  case(fsm)
   P1_GATE,P2_GATE: if(!read_issued) begin act_rd_en=1; act_rd_bank=1; act_rd_addr=9'd16+(row>>3); end
   P1_K: if(!read_issued) begin ivec_rd_en=1; ivec_rd_vector_sel=0; ivec_rd_word_addr=row>>3; end
   P1_STATE: if(!read_issued) begin state_rd_en=1; state_rd_bank=active_bank_in; state_rd_addr={row,chunk}; end
   P1_WRITE: begin state_wr_en=1; state_wr_bank=~active_bank_in; state_wr_addr={row,chunk}; end
   P1_V: if(!read_issued) begin ivec_rd_en=1; ivec_rd_vector_sel=1; ivec_rd_word_addr=chunk*4+vword; end
   P1_DIFF: begin
    act_wr_en=1; act_wr_bank=1; act_wr_addr=9'd32+chunk*2+diff_half; act_wr_data=write_data_q;
   end
   P2_D0: if(!read_issued) begin act_rd_en=1; act_rd_bank=1; act_rd_addr=9'd32+chunk*2; end
   P2_D1: if(!read_issued) begin act_rd_en=1; act_rd_bank=1; act_rd_addr=9'd33+chunk*2; end
   P2_K: if(!read_issued) begin ivec_rd_en=1; ivec_rd_vector_sel=0; ivec_rd_word_addr=row>>3; end
   P2_Q: if(!read_issued) begin ivec_rd_en=1; ivec_rd_vector_sel=2; ivec_rd_word_addr=row>>3; end
   P2_STATE: if(!read_issued) begin state_rd_en=1; state_rd_bank=~active_bank_in; state_rd_addr={row,chunk}; end
   P2_WRITE: begin state_wr_en=1; state_wr_bank=active_bank_in; state_wr_addr={row,chunk}; end
   P2_Y: begin
    act_wr_en=1; act_wr_bank=0; act_wr_addr=9'd160+chunk*2+diff_half; act_wr_data=write_data_q;
   end
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   done<=0; fsm<=IDLE; chunk<=0; group<=0; row<=0; diff_half<=0; read_issued<=0; vword<=0;
   gate_cache<=0; k_cache<=0; q_cache<=0; state_word<=0; state_build<=0; diff_cache<=0; v_cache<=0; write_data_q<=0; rq_data_q<=0;
   for(i=0;i<32;i=i+1) acc[i]<=0;
  end else begin
   done<=0;
   // A read request is a one-cycle pulse.  Waiting states never reissue it,
   // which prevents a delayed response for word N being consumed as word N+1.
   if((fsm==P1_GATE)||(fsm==P1_K)||(fsm==P1_STATE)||(fsm==P1_V)||
      (fsm==P2_D0)||(fsm==P2_D1)||(fsm==P2_GATE)||(fsm==P2_K)||
      (fsm==P2_Q)||(fsm==P2_STATE)) begin
    if(!read_issued) read_issued<=1;
   end
   case(fsm)
    IDLE: if(start) begin chunk<=0; row<=0; group<=0; read_issued<=0; for(i=0;i<32;i=i+1) acc[i]<=0; fsm<=P1_GATE; end
    P1_GATE: if(act_rd_valid) begin gate_cache<=act_rd_data; read_issued<=0; fsm<=P1_K; end
    P1_K: if(ivec_rd_valid) begin k_cache<=ivec_rd_data; read_issued<=0; fsm<=P1_STATE; end
    P1_STATE: if(state_rd_valid) begin state_word<=state_rd_data; state_build<=0; group<=0; fsm<=P1_GO; end
    P1_GO: fsm<=P1_WAIT;
    P1_WAIT: if(eng_out_valid) begin
     case(group) 0:state_build[63:0]<=eng_slice; 1:state_build[127:64]<=eng_slice; 2:state_build[191:128]<=eng_slice; default:state_build[255:192]<=eng_slice; endcase
     case(group)
      0:begin acc[0]<=acc[0]+t0;acc[1]<=acc[1]+t1;acc[2]<=acc[2]+t2;acc[3]<=acc[3]+t3;acc[4]<=acc[4]+t4;acc[5]<=acc[5]+t5;acc[6]<=acc[6]+t6;acc[7]<=acc[7]+t7;end
      1:begin acc[8]<=acc[8]+t0;acc[9]<=acc[9]+t1;acc[10]<=acc[10]+t2;acc[11]<=acc[11]+t3;acc[12]<=acc[12]+t4;acc[13]<=acc[13]+t5;acc[14]<=acc[14]+t6;acc[15]<=acc[15]+t7;end
      2:begin acc[16]<=acc[16]+t0;acc[17]<=acc[17]+t1;acc[18]<=acc[18]+t2;acc[19]<=acc[19]+t3;acc[20]<=acc[20]+t4;acc[21]<=acc[21]+t5;acc[22]<=acc[22]+t6;acc[23]<=acc[23]+t7;end
      default:begin acc[24]<=acc[24]+t0;acc[25]<=acc[25]+t1;acc[26]<=acc[26]+t2;acc[27]<=acc[27]+t3;acc[28]<=acc[28]+t4;acc[29]<=acc[29]+t5;acc[30]<=acc[30]+t6;acc[31]<=acc[31]+t7;end
     endcase
     if(group==3) fsm<=P1_COMMIT; else begin group<=group+1; fsm<=P1_GO; end
    end
    P1_COMMIT: fsm<=P1_WRITE;
    P1_WRITE: if(row==127) begin vword<=0; read_issued<=0; fsm<=P1_V; end else begin row<=row+1; read_issued<=0; fsm<=P1_GATE; end
    P1_V: if(ivec_rd_valid) begin
     case(vword) 0:v_cache[63:0]<=ivec_rd_data; 1:v_cache[127:64]<=ivec_rd_data; 2:v_cache[191:128]<=ivec_rd_data; default:v_cache[255:192]<=ivec_rd_data; endcase
     if(vword==3) begin diff_half<=0; fsm<=P1_DIFF_RQ; end else begin vword<=vword+1; read_issued<=0; end
    end
    P1_DIFF_RQ: begin
     if(!diff_half) for(i=0;i<16;i=i+1) rq_data_q[i*8 +:8]<=rq8(acc[i]);
     else for(i=0;i<16;i=i+1) rq_data_q[i*8 +:8]<=rq8(acc[i+16]);
     fsm<=P1_DIFF_PREP;
    end
    P1_DIFF_PREP: begin
     if(!diff_half) for(i=0;i<16;i=i+1) write_data_q[i*8 +:8]<=make_diff8($signed(v_cache[i*8 +:8]),$signed(rq_data_q[i*8 +:8]));
     else for(i=0;i<16;i=i+1) write_data_q[i*8 +:8]<=make_diff8($signed(v_cache[(i+16)*8 +:8]),$signed(rq_data_q[i*8 +:8]));
     fsm<=P1_DIFF;
    end
    P1_DIFF: if(diff_half) begin
     for(i=0;i<32;i=i+1) acc[i]<=0;
     if(chunk==3) begin chunk<=0; row<=0; read_issued<=0; fsm<=P2_D0; end else begin chunk<=chunk+1; row<=0; read_issued<=0; fsm<=P1_GATE; end
    end else begin diff_half<=1; fsm<=P1_DIFF_RQ; end
    P2_D0: if(act_rd_valid) begin diff_cache[127:0]<=act_rd_data; read_issued<=0; fsm<=P2_D1; end
    P2_D1: if(act_rd_valid) begin diff_cache[255:128]<=act_rd_data; read_issued<=0; fsm<=P2_GATE; end
    P2_GATE: if(act_rd_valid) begin gate_cache<=act_rd_data; read_issued<=0; fsm<=P2_K; end
    P2_K: if(ivec_rd_valid) begin k_cache<=ivec_rd_data; read_issued<=0; fsm<=P2_Q; end
    P2_Q: if(ivec_rd_valid) begin q_cache<=ivec_rd_data; read_issued<=0; fsm<=P2_STATE; end
    P2_STATE: if(state_rd_valid) begin state_word<=state_rd_data; state_build<=0; group<=0; fsm<=P2_GO; end
    P2_GO: fsm<=P2_WAIT;
    P2_WAIT: if(eng_out_valid) begin
     case(group) 0:state_build[63:0]<=eng_slice; 1:state_build[127:64]<=eng_slice; 2:state_build[191:128]<=eng_slice; default:state_build[255:192]<=eng_slice; endcase
     case(group)
      0:begin acc[0]<=acc[0]+t0;acc[1]<=acc[1]+t1;acc[2]<=acc[2]+t2;acc[3]<=acc[3]+t3;acc[4]<=acc[4]+t4;acc[5]<=acc[5]+t5;acc[6]<=acc[6]+t6;acc[7]<=acc[7]+t7;end
      1:begin acc[8]<=acc[8]+t0;acc[9]<=acc[9]+t1;acc[10]<=acc[10]+t2;acc[11]<=acc[11]+t3;acc[12]<=acc[12]+t4;acc[13]<=acc[13]+t5;acc[14]<=acc[14]+t6;acc[15]<=acc[15]+t7;end
      2:begin acc[16]<=acc[16]+t0;acc[17]<=acc[17]+t1;acc[18]<=acc[18]+t2;acc[19]<=acc[19]+t3;acc[20]<=acc[20]+t4;acc[21]<=acc[21]+t5;acc[22]<=acc[22]+t6;acc[23]<=acc[23]+t7;end
      default:begin acc[24]<=acc[24]+t0;acc[25]<=acc[25]+t1;acc[26]<=acc[26]+t2;acc[27]<=acc[27]+t3;acc[28]<=acc[28]+t4;acc[29]<=acc[29]+t5;acc[30]<=acc[30]+t6;acc[31]<=acc[31]+t7;end
     endcase
     if(group==3) fsm<=P2_COMMIT; else begin group<=group+1; fsm<=P2_GO; end
    end
    P2_COMMIT: fsm<=P2_WRITE;
    P2_WRITE: if(row==127) begin diff_half<=0; fsm<=P2_Y_PREP; end else begin row<=row+1; read_issued<=0; fsm<=P2_GATE; end
    P2_Y_PREP: begin
     if(!diff_half) for(i=0;i<16;i=i+1) write_data_q[i*8 +:8]<=rq8(acc[i]);
     else for(i=0;i<16;i=i+1) write_data_q[i*8 +:8]<=rq8(acc[i+16]);
     fsm<=P2_Y;
    end
    P2_Y: if(diff_half) begin
     for(i=0;i<32;i=i+1) acc[i]<=0;
     if(chunk==3) begin done<=1; fsm<=IDLE; end else begin chunk<=chunk+1; row<=0; read_issued<=0; fsm<=P2_D0; end
    end else begin diff_half<=1; fsm<=P2_Y_PREP; end
   endcase
  end
 end
endmodule
