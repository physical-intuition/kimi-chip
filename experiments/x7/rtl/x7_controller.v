`timescale 1ns/1ps
// Synthesizable schedule-accounting controller used by x7_top. Datapath phase
// transitions remain event-driven; this block records exact per-phase cycles.
module x7_controller(input wire clk,input wire rst_n,input wire [6:0] phase,
 output reg [15:0] phase_cycles,output reg [6:0] phase_q);
 always @(posedge clk)begin
  if(!rst_n)begin phase_q<=0;phase_cycles<=0;end
  else if(phase!=phase_q)begin phase_q<=phase;phase_cycles<=1;end
  else phase_cycles<=phase_cycles+1'b1;
 end
endmodule
