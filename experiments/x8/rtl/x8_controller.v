`timescale 1ns/1ps
module x8_controller(
 input wire clk,input wire rst_n,input wire token_valid,output wire token_ready,
 output reg busy,output reg done,output reg [3:0] phase,output reg [7:0] phase_cycle,
 output reg [5:0] weight_rd_en,output reg [47:0] weight_rd_addr,
 output reg mac0_valid,output reg mac1_valid,output reg conv_valid,
 output reg state_rd_en,output reg state_wr_en,output reg state_rd_bank,output reg state_wr_bank,
 output reg [6:0] state_row,
 output reg o_input_valid,output reg norm_valid,output reg residual_valid,
 output reg [5:0] bank_seen,output reg [1:0] state_bank_seen
);
 localparam IDLE=0,K_PROJ=1,V_PROJ=2,Q_PROJ=3,CONV=4,STATE_P1=5,
            STATE_D=6,STATE_P2=7,O_PROJ=8,NORM=9,RESIDUAL=10;
 reg current_state_bank;
 reg state_p2_complete;
 reg [7:0] matrix_base;
 integer b;
 assign token_ready=!busy;
 function [7:0] phase_last; input [3:0] p; begin case(p)
   K_PROJ:phase_last=85; V_PROJ:phase_last=85; Q_PROJ:phase_last=85;
   CONV:phase_last=9; STATE_P1:phase_last=127; STATE_D:phase_last=1;
   STATE_P2:phase_last=127; O_PROJ:phase_last=85; NORM:phase_last=23;
   RESIDUAL:phase_last=7; default:phase_last=0; endcase end endfunction
 always @* begin
   case(phase) K_PROJ:matrix_base=0;V_PROJ:matrix_base=43;Q_PROJ:matrix_base=86;O_PROJ:matrix_base=129;default:matrix_base=172;endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin busy<=0;done<=0;phase<=IDLE;phase_cycle<=0;current_state_bank<=0;state_p2_complete<=0;
    weight_rd_en<=0;weight_rd_addr<=0;mac0_valid<=0;mac1_valid<=0;conv_valid<=0;
    state_rd_en<=0;state_wr_en<=0;state_rd_bank<=0;state_wr_bank<=1;state_row<=0;
    o_input_valid<=0;norm_valid<=0;residual_valid<=0;bank_seen<=0;state_bank_seen<=0;
  end else begin
   done<=0;weight_rd_en<=0;mac0_valid<=0;mac1_valid<=0;conv_valid<=0;
   state_rd_en<=0;state_wr_en<=0;o_input_valid<=0;norm_valid<=0;residual_valid<=0;
   if(!busy) begin
    if(token_valid) begin busy<=1;phase<=K_PROJ;phase_cycle<=0;bank_seen<=0;state_bank_seen<=0;state_p2_complete<=0;end
   end else begin
    if((phase==K_PROJ)||(phase==V_PROJ)||(phase==Q_PROJ)||(phase==O_PROJ)) begin
      mac0_valid<=1;mac1_valid<=1;
      if(phase_cycle<43) begin
        weight_rd_en<=6'h3f;
        for(b=0;b<6;b=b+1) weight_rd_addr[b*8+:8]<=matrix_base+phase_cycle;
        bank_seen<=bank_seen|6'h3f;
      end
      if(phase==O_PROJ) begin o_input_valid<=state_p2_complete; if(!state_p2_complete) busy<=0; end
    end
    if(phase==CONV) begin
      conv_valid<=1;
      // Prefetch old-state row zero on the final conv cycle, hiding SRAM latency.
      if(phase_cycle==9) begin state_rd_en<=1;state_rd_bank<=current_state_bank;state_row<=0;state_bank_seen[current_state_bank]<=1;end
    end
    if(phase==STATE_P1) begin
      state_rd_en<=1;state_wr_en<=1;state_rd_bank<=current_state_bank;state_wr_bank<=~current_state_bank;
      state_row<=phase_cycle[6:0];state_bank_seen<=2'b11;
    end
    if(phase==STATE_D) begin
      // Prefetch A row zero while d=beta(v-u) is formed.
      if(phase_cycle==1) begin state_rd_en<=1;state_rd_bank<=~current_state_bank;state_row<=0;state_bank_seen[~current_state_bank]<=1;end
    end
    if(phase==STATE_P2) begin
      state_rd_en<=1;state_wr_en<=1;state_rd_bank<=~current_state_bank;state_wr_bank<=current_state_bank;
      state_row<=phase_cycle[6:0];state_bank_seen<=2'b11;
      if(phase_cycle==127) state_p2_complete<=1;
    end
    if(phase==NORM) norm_valid<=1;
    if(phase==RESIDUAL) residual_valid<=1;
    if(phase_cycle==phase_last(phase)) begin
      phase_cycle<=0;
      case(phase)
       K_PROJ:phase<=V_PROJ;V_PROJ:phase<=Q_PROJ;Q_PROJ:phase<=CONV;
       CONV:phase<=STATE_P1;STATE_P1:phase<=STATE_D;STATE_D:phase<=STATE_P2;
       STATE_P2:phase<=O_PROJ;O_PROJ:phase<=NORM;NORM:phase<=RESIDUAL;
       RESIDUAL:begin phase<=IDLE;busy<=0;done<=1;current_state_bank<=~current_state_bank;end
       default:begin phase<=IDLE;busy<=0;end
      endcase
    end else phase_cycle<=phase_cycle+1'b1;
   end
  end
 end
endmodule
