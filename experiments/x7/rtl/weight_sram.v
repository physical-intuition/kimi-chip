`timescale 1ns/1ps
// Four independent 16 KiB matrices. Y3 registers the matrix output through a
// two-level 2:1 tree, avoiding the former wide 4:1 SRAM-output mux.
module weight_sram (
 input wire clk,
 input wire prog_en, input wire [1:0] prog_matrix, input wire [1:0] prog_bank,
 input wire [8:0] prog_addr, input wire [63:0] prog_data,
 input wire rd_en, input wire [1:0] rd_matrix, input wire [8:0] rd_addr,
 output reg [255:0] rd_data
);
 wire [63:0] q[0:15];
 reg [1:0] rd_matrix_q;
 reg rd_matrix_hi_q;
 reg [255:0] rd_lo_q,rd_hi_q;
 genvar m,b;
 generate for(m=0;m<4;m=m+1) begin: gm
   for(b=0;b<4;b=b+1) begin: gb
     wire selp=prog_en&&(prog_matrix==m)&&(prog_bank==b);
     wire selr=rd_en&&(rd_matrix==m);
     fakeram45_512x64 ram(.clk(clk),.ce_in(selp|selr),.we_in(selp),
       .addr_in(selp?prog_addr:rd_addr),.wd_in(prog_data),.rd_out(q[m*4+b]));
   end
 end endgenerate
 always @(posedge clk) begin
   if(rd_en) rd_matrix_q<=rd_matrix;
   if(rd_matrix_q[0]) begin
    rd_lo_q<={q[7],q[6],q[5],q[4]};
    rd_hi_q<={q[15],q[14],q[13],q[12]};
   end else begin
    rd_lo_q<={q[3],q[2],q[1],q[0]};
    rd_hi_q<={q[11],q[10],q[9],q[8]};
   end
   rd_matrix_hi_q<=rd_matrix_q[1];
   rd_data<=rd_matrix_hi_q?rd_hi_q:rd_lo_q;
 end
endmodule
