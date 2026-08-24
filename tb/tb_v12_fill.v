`timescale 1ns/1ps
module fakeram45_512x64(input clk,ce_in,we_in,input [8:0] addr_in,input [63:0] wd_in,w_mask_in,output reg [63:0] rd_out);
 reg [63:0] mem[0:511];
 always @(posedge clk) if(ce_in) begin
   if(we_in) mem[addr_in]<=(mem[addr_in]&~w_mask_in)|(wd_in&w_mask_in);
   else rd_out<=mem[addr_in];
 end
endmodule
module tb_k1;
 reg clk=0,rst_n=0,start=0,h_we=0,h_sel=0; reg [11:0] h_addr=0; reg [63:0] h_wdata=0;
 reg [15:0] k_dim=0; reg [7:0] r_addr=0; wire done; wire [23:0] r_data;
 fullchip_v12 dut(.clk(clk),.rst_n(rst_n),.h_we(h_we),.h_sel(h_sel),.h_addr(h_addr),
   .h_wdata(h_wdata),.start(start),.k_dim(k_dim),.done(done),.r_addr(r_addr),.r_data(r_data));
 always #1 clk=~clk; integer i,t0;
 task load(input sel,input [11:0] a,input [63:0] d);
   begin @(negedge clk); h_we=1; h_sel=sel; h_addr=a; h_wdata=d; @(negedge clk); h_we=0; end
 endtask
 task run_k(input [15:0] K);
   begin k_dim=K; @(negedge clk); start=1; @(negedge clk); start=0; t0=$time;
     while(!done) begin #2; if($time-t0>4000) begin $display("TO"); $finish; end end #4; end
 endtask
 initial begin #4 rst_n=1;
  // element i -> weight all-lanes = (i%7)+1, activation all-lanes = (i%5)+1
  for (i=0;i<40;i=i+1) begin load(0,i[11:0],{16{((i%7)+1)}}); load(1,i[11:0],{16{((i%5)+1)}}); end
  run_k(1);  r_addr=0;      #2; $display("K=1 acc[0][0]=%0d exp=%0d %s", $signed(r_data), 1*1, ($signed(r_data)===1)?"PASS":"FAIL");
  run_k(2);  r_addr=0;      #2; $display("K=2 acc[0][0]=%0d exp=%0d %s", $signed(r_data), 1*1+2*2, ($signed(r_data)===5)?"PASS":"FAIL");
  run_k(3);  r_addr=0;      #2; $display("K=3 acc[0][0]=%0d exp=%0d %s", $signed(r_data), 1*1+2*2+3*3, ($signed(r_data)===14)?"PASS":"FAIL");
  $finish; end
endmodule
