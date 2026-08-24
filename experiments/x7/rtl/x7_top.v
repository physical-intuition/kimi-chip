`timescale 1ns/1ps
// Y3 timing-closed SRAM-streaming KDA top. Projection, gates, state, norm,
// residual, and output all use the hard SRAMs as canonical stores.
module x7_top(
 input wire clk,input wire rst_n,
 input wire in_valid,output wire in_ready,input wire [127:0] in_data,input wire in_last,
 output wire out_valid,input wire out_ready,output wire [127:0] out_data,output wire out_last,
 input wire weight_prog_en,input wire [1:0] weight_prog_matrix,input wire [1:0] weight_prog_bank,
 input wire [8:0] weight_prog_addr,input wire [63:0] weight_prog_data,
 input wire state_prog_en,input wire state_prog_bank,input wire [1:0] state_prog_lane,
 input wire [8:0] state_prog_addr,input wire [63:0] state_prog_data,
 input wire conv_prog_en,input wire [6:0] conv_prog_channel,input wire [31:0] conv_prog_alpha,input wire [31:0] conv_prog_beta,
 input wire state_debug_en,input wire state_debug_bank,input wire [8:0] state_debug_addr,
 output wire [255:0] state_debug_data,output wire busy,output reg fault
);
 localparam [6:0] P_IDLE=7'b0000001,P_PROJ=7'b0000010,P_CONV=7'b0000100,
 P_P1_INIT=7'b0001000,P_P1=7'b0010000,P_NORM=7'b0100000,P_OUTPUT=7'b1000000;
 reg[6:0] phase; wire[15:0] phase_cycles; wire[6:0] phase_q;
 x7_controller ctl(.clk(clk),.rst_n(rst_n),.phase(phase),.phase_cycles(phase_cycles),.phase_q(phase_q));
 assign busy=phase!=P_IDLE; assign in_ready=phase==P_IDLE;
 integer i;
 reg [3:0] input_beat;

 // Activation A handles input/program/read scheduling. B writes streamed Y and
 // packed conv gates, avoiding same-bank port collisions.
 reg acta_en,acta_we,acta_bank; reg[8:0] acta_addr; reg[127:0] acta_wdata;
 reg actb_en,actb_we,actb_bank; reg[8:0] actb_addr; reg[127:0] actb_wdata;
 wire[127:0] acta_rdata,actb_rdata;
 activation_sram activations(.clk(clk),.en(acta_en),.we(acta_we),.buffer_sel(acta_bank),.addr(acta_addr),.wdata(acta_wdata),.rdata(acta_rdata),
  .en_b(actb_en),.we_b(actb_we),.buffer_sel_b(actb_bank),.addr_b(actb_addr),.wdata_b(actb_wdata),.rdata_b(actb_rdata));

 // Projection schedule: A-read low beat, A-read high beat, weight-read, wait,
 // MAC pulse, result wait. Each source window covers 32 bytes.
 reg[2:0] proj_step; reg[1:0] proj_sel; reg[8:0] proj_index; reg[7:0] proj_results;
 reg[127:0] proj_low; reg[255:0] proj_window,proj_weight;
 wire[6:0] proj_row=proj_index[8:2]; wire[1:0] proj_chunk=proj_index[1:0];
 // Weight SRAM reads are synchronous. Step 2 issues the request, step 3 is
 // the macro latency bubble, step 4 captures rd_data, and step 5 launches MAC.
 wire proj_weight_issue=(phase==P_PROJ)&&(proj_step==3'd2);
 wire proj_mac_pulse=(phase==P_PROJ)&&(proj_step==3'd6);
 wire[255:0] weight_rd_data;
 weight_sram weights(.clk(clk),.prog_en(weight_prog_en&&(phase==P_IDLE)),.prog_matrix(weight_prog_matrix),.prog_bank(weight_prog_bank),.prog_addr(weight_prog_addr),.prog_data(weight_prog_data),.rd_en(proj_weight_issue),.rd_matrix(proj_sel),.rd_addr(proj_index),.rd_data(weight_rd_data));
 wire mac_result_valid; wire signed[23:0] mac_result; wire signed[7:0] mac_q;
 mac_array_16x16 mac(.clk(clk),.rst_n(rst_n),.clear(proj_mac_pulse&&(proj_chunk==0)),.valid(proj_mac_pulse),.last(proj_mac_pulse&&(proj_chunk==3)),.weights(proj_weight),.activations(proj_window),.result_valid(mac_result_valid),.result(mac_result));
 requant rq(.in_data(mac_result),.out_data(mac_q));
 wire[3:0] ivec_wr_en=mac_result_valid?(4'b0001<<proj_sel):4'b0000;
 wire[255:0] ivec_rd_words;
 (* keep_hierarchy = "yes", keep = "true" *) intermediate_sram ivecs(.clk(clk),.wr_en(ivec_wr_en),.wr_index(proj_results[6:0]),.wr_data(mac_q),.rd_en(ss_ivec_rd_en ? (4'b0001 << ss_ivec_vec) : (norm_ivec_rd_en ? 4'b1000 : 4'b0000)),.rd_word_addr(ss_ivec_rd_en ? {2'b00,ss_ivec_addr} : {2'b00,norm_ivec_rd_addr}),.rd_words(ivec_rd_words));

 // Conv reads one X beat then a channel's programmed parameters. Eight ordered
 // {beta,alpha} pairs are packed into each bank1 gate beat (16..31).
 reg[2:0] conv_step; reg[6:0] conv_channel; reg[127:0] conv_x_beat,conv_gate_pack; reg signed[7:0] conv_x_scalar;
 wire conv_pulse=(phase==P_CONV)&&(conv_step==3'd3);
 wire conv_out_valid; wire[7:0] conv_alpha; wire signed[7:0] conv_beta;
 conv_unit_serial conv(.clk(clk),.rst_n(rst_n),.valid(conv_pulse),.x(conv_x_scalar),.alpha_w(acta_rdata[31:0]),.beta_w(acta_rdata[63:32]),.out_valid(conv_out_valid),.alpha(conv_alpha),.beta(conv_beta));

 // State pass is a standalone SRAM client. Wrapper read valids are one delayed
 // request, matching the synchronous macro interfaces.
 wire ss_done; wire ss_active_out;
 wire ss_state_rd_en,ss_state_rd_bank,ss_state_wr_en,ss_state_wr_bank;
 wire [8:0] ss_state_rd_addr,ss_state_wr_addr; wire [255:0] ss_state_wr_data;
 wire ss_act_rd_en,ss_act_rd_bank,ss_act_wr_en,ss_act_wr_bank;
 wire [8:0] ss_act_rd_addr,ss_act_wr_addr; wire [127:0] ss_act_wr_data;
 wire ss_ivec_rd_en; wire [1:0] ss_ivec_vec; wire [3:0] ss_ivec_addr;
 // Macro outputs are synchronous and already registered. A one-cycle delayed
 // request valid is aligned with those outputs; do not register read data again.
 reg ss_state_rd_valid,ss_act_rd_valid,ss_ivec_rd_valid,ss_ivec_rd_valid_q2;
 reg [1:0] ss_ivec_vec_q; reg [63:0] ss_ivec_rdata_q;
 wire norm_ivec_rd_en; wire [3:0] norm_ivec_rd_addr; wire norm_act_rd_en; wire [8:0] norm_act_rd_addr; wire norm_act_wr_en; wire [8:0] norm_act_wr_addr; wire [127:0] norm_act_wr_data; wire norm_done;
 reg norm_ivec_rd_valid,norm_ivec_rd_valid_q2,norm_act_rd_valid; reg [1:0] norm_ivec_vec_q; reg [63:0] norm_ivec_rdata_q;
 reg active_state;
 wire [255:0] state_rd_data;
 state_stream_controller state_stream(.clk(clk),.rst_n(rst_n),.start(phase==P_P1_INIT),.done(ss_done),.active_bank_in(active_state),.active_bank_out(ss_active_out),
  .state_rd_en(ss_state_rd_en),.state_rd_bank(ss_state_rd_bank),.state_rd_addr(ss_state_rd_addr),.state_rd_data(state_rd_data),.state_rd_valid(ss_state_rd_valid),.state_wr_en(ss_state_wr_en),.state_wr_bank(ss_state_wr_bank),.state_wr_addr(ss_state_wr_addr),.state_wr_data(ss_state_wr_data),
  .act_rd_en(ss_act_rd_en),.act_rd_bank(ss_act_rd_bank),.act_rd_addr(ss_act_rd_addr),.act_rd_data(acta_rdata),.act_rd_valid(ss_act_rd_valid),.act_wr_en(ss_act_wr_en),.act_wr_bank(ss_act_wr_bank),.act_wr_addr(ss_act_wr_addr),.act_wr_data(ss_act_wr_data),
  .ivec_rd_en(ss_ivec_rd_en),.ivec_rd_vector_sel(ss_ivec_vec),.ivec_rd_word_addr(ss_ivec_addr),.ivec_rd_data(ss_ivec_rdata_q),.ivec_rd_valid(ss_ivec_rd_valid_q2));
 wire state_rd_en=ss_state_rd_en||state_debug_en;
 wire state_rd_bank=state_debug_en?state_debug_bank:ss_state_rd_bank;
 wire [8:0] state_rd_addr=state_debug_en?state_debug_addr:ss_state_rd_addr;
 state_sram states(.clk(clk),.prog_en(state_prog_en&&(phase==P_IDLE)),.prog_bank(state_prog_bank),.prog_lane(state_prog_lane),.prog_addr(state_prog_addr),.prog_data(state_prog_data),.rd_en(state_rd_en),.rd_bank(state_rd_bank),.rd_addr(state_rd_addr),.wr_en(ss_state_wr_en),.wr_bank(ss_state_wr_bank),.wr_addr(ss_state_wr_addr),.wr_data(ss_state_wr_data),.rd_data(state_rd_data));
 assign state_debug_data=state_rd_data;
 reg norm_started; streaming_norm norm(.clk(clk),.rst_n(rst_n),.start((phase==P_NORM)&&!norm_started),.ivec_rd_en(norm_ivec_rd_en),.ivec_rd_addr(norm_ivec_rd_addr),.ivec_rd_data(norm_ivec_rdata_q),.ivec_rd_valid(norm_ivec_rd_valid_q2),.act_rd_en(norm_act_rd_en),.act_rd_addr(norm_act_rd_addr),.act_rd_data(acta_rdata),.act_rd_valid(norm_act_rd_valid),.act_wr_en(norm_act_wr_en),.act_wr_addr(norm_act_wr_addr),.act_wr_data(norm_act_wr_data),.done(norm_done));
 reg out_pending; reg[3:0] out_issue; reg[2:0] out_index; reg[3:0] y_beat;
 assign out_valid=(phase==P_OUTPUT)&&out_pending; assign out_data=acta_rdata; assign out_last=out_index==7;
 function signed[7:0] rq8; input signed[23:0]a; reg signed[23:0]s; begin s=a>>>8;if(s>127)rq8=127;else if(s< -128)rq8=-128;else rq8=s[7:0];end endfunction
 function signed[7:0] make_diff; input signed[7:0]vv;input signed[23:0]uu;reg signed[8:0]z;begin z=vv-rq8(uu);if(z>127)make_diff=127;else if(z< -128)make_diff=-128;else make_diff=z[7:0];end endfunction

 always @* begin
  acta_en=0;acta_we=0;acta_bank=0;acta_addr=0;acta_wdata=0;
  actb_en=0;actb_we=0;actb_bank=0;actb_addr=0;actb_wdata=0;
  case(phase)
   P_IDLE: begin
    if(in_valid) begin acta_en=1;acta_we=1;acta_addr=input_beat;acta_wdata=in_data;end
    if(conv_prog_en) begin acta_en=1;acta_we=1;acta_addr=9'd16+conv_prog_channel;acta_wdata={64'd0,conv_prog_beta,conv_prog_alpha};end
   end
   P_PROJ: begin
    if(proj_step==0) begin acta_en=1;acta_addr=((proj_sel==3)?9'd160:9'd0)+{6'd0,proj_chunk,1'b0};end
    else if(proj_step==1) begin acta_en=1;acta_addr=((proj_sel==3)?9'd160:9'd0)+{6'd0,proj_chunk,1'b1};end
   end
   P_CONV: begin
    if(conv_step==0) begin acta_en=1;acta_addr={5'd0,conv_channel[6:4]};end
    else if(conv_step==1) begin acta_en=1;acta_addr=9'd16+conv_channel;end
    if(conv_step==5) begin actb_en=1;actb_we=1;actb_bank=1;actb_addr=9'd16+{3'd0,conv_channel[6:3]};actb_wdata=conv_gate_pack;end
   end
   P_P1: begin
    if(ss_act_rd_en) begin acta_en=1;acta_bank=ss_act_rd_bank;acta_addr=ss_act_rd_addr;end
    if(ss_act_wr_en) begin actb_en=1;actb_we=1;actb_bank=ss_act_wr_bank;actb_addr=ss_act_wr_addr;actb_wdata=ss_act_wr_data;end
   end
   P_NORM: begin
    if(norm_act_rd_en) begin acta_en=1;acta_bank=0;acta_addr=norm_act_rd_addr;end
    if(norm_act_wr_en) begin actb_en=1;actb_we=1;actb_bank=1;actb_addr=norm_act_wr_addr;actb_wdata=norm_act_wr_data;end
   end
   P_OUTPUT: if(((!out_pending)||out_ready)&&(out_issue<8)) begin acta_en=1;acta_bank=1;acta_addr=out_issue;end
  endcase
 end

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin phase<=P_IDLE;fault<=0;input_beat<=0;proj_step<=0;proj_sel<=0;proj_index<=0;proj_results<=0;conv_step<=0;conv_channel<=0;conv_gate_pack<=0;conv_x_scalar<=0;active_state<=0;norm_started<=0;norm_ivec_rd_valid<=0;norm_ivec_rd_valid_q2<=0;norm_ivec_rdata_q<=0;norm_act_rd_valid<=0;norm_ivec_vec_q<=3;out_pending<=0;out_issue<=0;out_index<=0;ss_state_rd_valid<=0;ss_act_rd_valid<=0;ss_ivec_rd_valid<=0;ss_ivec_rd_valid_q2<=0;ss_ivec_vec_q<=0;ss_ivec_rdata_q<=0;end
  else begin
   ss_state_rd_valid<=ss_state_rd_en;
   ss_act_rd_valid<=ss_act_rd_en;
   ss_ivec_rd_valid<=ss_ivec_rd_en; ss_ivec_rd_valid_q2<=ss_ivec_rd_valid;
   norm_ivec_rd_valid<=norm_ivec_rd_en; norm_ivec_rd_valid_q2<=norm_ivec_rd_valid; norm_act_rd_valid<=norm_act_rd_en;
   if(ss_ivec_rd_en) ss_ivec_vec_q<=ss_ivec_vec;
   if(ss_ivec_rd_valid) case(ss_ivec_vec_q) 0:ss_ivec_rdata_q<=ivec_rd_words[63:0];1:ss_ivec_rdata_q<=ivec_rd_words[127:64];2:ss_ivec_rdata_q<=ivec_rd_words[191:128];default:ss_ivec_rdata_q<=ivec_rd_words[255:192];endcase
   if(norm_ivec_rd_en) norm_ivec_vec_q<=2'd3;
   if(norm_ivec_rd_valid) norm_ivec_rdata_q<=ivec_rd_words[255:192];
   case(phase)
   P_IDLE: begin out_pending<=0;if(in_valid)begin if((input_beat==7)!=in_last)fault<=1;if(input_beat==7)begin input_beat<=0;proj_sel<=0;proj_index<=0;proj_results<=0;proj_step<=0;phase<=P_PROJ;end else input_beat<=input_beat+1;end end
   P_PROJ: case(proj_step)
    // Read the two 16-byte activation beats that make one 32-byte MAC window.
    0:proj_step<=1;
    1:begin proj_low<=acta_rdata;proj_step<=2;end
    // Issue the corresponding 32-byte weight row/chunk read while the high
    // activation beat becomes visible.
    2:begin proj_window<={acta_rdata,proj_low};proj_step<=3;end
    3:proj_step<=4;
    4:proj_step<=5;
    5:begin proj_weight<=weight_rd_data;proj_step<=6;end
    // The MAC accumulates four chunks per output row. Only chunk 3 generates
    // a result; earlier chunks advance the weight/source chunk immediately.
    6:begin
      if(proj_chunk==3) proj_step<=7;
      else begin proj_index<=proj_index+1;proj_step<=0;end
    end
    7:if(mac_result_valid)begin
      if(proj_results==127)begin
        proj_results<=0;proj_index<=0;proj_step<=0;
        if(proj_sel==2)begin conv_channel<=0;conv_step<=0;phase<=P_CONV;end
        else if(proj_sel==3)begin norm_started<=0;phase<=P_NORM;end
        else proj_sel<=proj_sel+1;
      end else begin
        proj_results<=proj_results+1;proj_index<=proj_index+1;proj_step<=0;
      end
    end
   endcase
   P_CONV: case(conv_step)
    0:conv_step<=1;
    1:begin conv_x_beat<=acta_rdata;conv_step<=2;end
    2:begin conv_x_scalar<=conv_x_beat[conv_channel[3:0]*8 +:8];conv_step<=3;end
    3:conv_step<=4;
    4:if(conv_out_valid)begin
      conv_gate_pack[conv_channel[2:0]*16+:16]<={conv_beta,conv_alpha};
      if(conv_channel[2:0]==7)conv_step<=5;else begin conv_channel<=conv_channel+1;conv_step<=0;end
    end
    5:if(conv_channel==127)phase<=P_P1_INIT;else begin conv_channel<=conv_channel+1;conv_step<=0;end
   endcase
   P_P1_INIT: phase<=P_P1;
   P_P1: if(ss_done) begin active_state<=ss_active_out;proj_sel<=3;proj_index<=0;proj_results<=0;proj_step<=0;phase<=P_PROJ;end
   P_NORM:begin norm_started<=1;if(norm_done)begin out_issue<=0;out_pending<=0;phase<=P_OUTPUT;end end
   P_OUTPUT:begin if(out_pending&&out_ready)out_pending<=0;if((!out_pending)||out_ready)begin if(out_issue<8)begin out_pending<=1;out_index<=out_issue[2:0];out_issue<=out_issue+1;end else if(out_pending&&out_ready)phase<=P_IDLE;end end
   endcase
  end
 end
endmodule
