`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// KDA State with SRAM Macro Backend
//
// Uses fakeram45_256x32 for storage instead of behavioral memory.
// Each head's 16x16 state matrix stored as 256 words (16 rows × 16 cols).
//
// Interface is row-at-a-time for SRAM compatibility:
//   - Read one row (16 elements × 32-bit) over 16 cycles
//   - Write one row (16 elements × 32-bit) over 16 cycles
//
// Parameters (X1Y5 config):
//   KDA_HEADS = 2
//   KDA_DIM = 16
//   State per head = 16 × 16 × 32-bit = 8192 bits = 256 words
//-----------------------------------------------------------------------------
module kda_state_sram_backed #(
    parameter KDA_HEADS = 2,
    parameter KDA_DIM   = 16  // Must be 16 for this SRAM config
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // Control
    input  wire                         state_reset,
    
    // Sequential read: one element per cycle
    input  wire                         rd_start,      // Start read sequence
    input  wire [(KDA_HEADS)-1:0] rd_head,
    input  wire [(KDA_DIM)-1:0]   rd_row,
    input  wire [(KDA_DIM)-1:0]   rd_col,
    output wire [31:0]                  rd_data,
    output wire                         rd_valid,
    
    // Sequential write: one element per cycle  
    input  wire                         wr_en,
    input  wire [(KDA_HEADS)-1:0] wr_head,
    input  wire [(KDA_DIM)-1:0]   wr_row,
    input  wire [(KDA_DIM)-1:0]   wr_col,
    input  wire [31:0]                  wr_data
);

    // SRAM signals for head 0
    wire        sram0_ce, sram0_we;
    wire [7:0]  sram0_addr;  // 256 depth = 8 bits
    wire [31:0] sram0_wd, sram0_rd;
    wire [31:0] sram0_wmask;
    
    // SRAM signals for head 1
    wire        sram1_ce, sram1_we;
    wire [7:0]  sram1_addr;
    wire [31:0] sram1_wd, sram1_rd;
    wire [31:0] sram1_wmask;
    
    // Address calculation: addr = row * KDA_DIM + col
    wire [7:0] rd_addr = {rd_row, rd_col};
    wire [7:0] wr_addr = {wr_row, wr_col};
    
    // Head 0 control
    assign sram0_ce = (rd_start && rd_head == 0) || (wr_en && wr_head == 0);
    assign sram0_we = wr_en && wr_head == 0;
    assign sram0_addr = sram0_we ? wr_addr : rd_addr;
    assign sram0_wd = wr_data;
    assign sram0_wmask = 32'hFFFFFFFF;
    
    // Head 1 control
    assign sram1_ce = (rd_start && rd_head == 1) || (wr_en && wr_head == 1);
    assign sram1_we = wr_en && wr_head == 1;
    assign sram1_addr = sram1_we ? wr_addr : rd_addr;
    assign sram1_wd = wr_data;
    assign sram1_wmask = 32'hFFFFFFFF;
    
    // Read valid pipeline (1 cycle latency)
    reg rd_valid_r;
    reg rd_head_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_valid_r <= 1'b0;
            rd_head_r <= 1'b0;
        end else begin
            rd_valid_r <= rd_start;
            rd_head_r <= rd_head;
        end
    end
    assign rd_valid = rd_valid_r;
    assign rd_data = rd_head_r ? sram1_rd : sram0_rd;
    
    // Instantiate SRAM macros
    // Note: fakeram45_256x32 has depth=256, width=32
    fakeram45_256x32 sram_head0 (
        .clk(clk),
        .ce_in(sram0_ce),
        .we_in(sram0_we),
        .addr_in(sram0_addr),
        .wd_in(sram0_wd),
        .w_mask_in(sram0_wmask),
        .rd_out(sram0_rd)
    );
    
    fakeram45_256x32 sram_head1 (
        .clk(clk),
        .ce_in(sram1_ce),
        .we_in(sram1_we),
        .addr_in(sram1_addr),
        .wd_in(sram1_wd),
        .w_mask_in(sram1_wmask),
        .rd_out(sram1_rd)
    );

endmodule
