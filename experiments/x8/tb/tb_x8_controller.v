`timescale 1ns/1ps
module tb_x8_controller;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,token_valid=0;
 wire token_ready,busy,done;wire[3:0]phase;wire[7:0]phase_cycle;wire[5:0]weight_rd_en;wire[47:0]weight_rd_addr;
 wire mac0_valid,mac1_valid,conv_valid,state_rd_en,state_wr_en,state_rd_bank,state_wr_bank;wire[6:0]state_row;
 wire o_input_valid,norm_valid,residual_valid;wire[5:0]bank_seen;wire[1:0]state_bank_seen;
 integer cycles=0,failures=0,p1=0,p2=0,op=0,mac_cycles=0;reg saw_o_before_p2=0,saw_p2_end=0;
 x8_controller dut(.*);
 always @(posedge clk) if(rst_n&&busy) begin
   cycles=cycles+1;
   if(phase==5)p1=p1+1;if(phase==7)begin p2=p2+1;if(phase_cycle==127)saw_p2_end=1;end
   if(phase==8)begin op=op+1;if(o_input_valid&&!saw_p2_end)saw_o_before_p2=1;end
   if(mac0_valid&&mac1_valid)mac_cycles=mac_cycles+1;
 end
 initial begin
  repeat(3)@(posedge clk);rst_n=1;@(negedge clk);token_valid=1;@(negedge clk);token_valid=0;
  wait(done);#1;
  if(cycles!=644)begin $display("FAIL cycles %0d",cycles);failures=failures+1;end
  if(bank_seen!=6'h3f)begin $display("FAIL bank_seen %h",bank_seen);failures=failures+1;end
  if(state_bank_seen!=2'b11)begin $display("FAIL state banks %b",state_bank_seen);failures=failures+1;end
  if(p1!=128||p2!=128||op!=86)begin $display("FAIL phase counts p1=%0d p2=%0d o=%0d",p1,p2,op);failures=failures+1;end
  if(saw_o_before_p2)begin $display("FAIL O before P2");failures=failures+1;end
  if(mac_cycles!=344)begin $display("FAIL MAC cycles %0d",mac_cycles);failures=failures+1;end
  if(failures==0)$display("PASS X8 controller: 644 cycles, six banks, ping-pong, O after state_p2, MACs active");
  $finish_and_return(failures!=0);
 end
endmodule
