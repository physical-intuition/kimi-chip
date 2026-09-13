`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Behavioral model for fakeram45_256x32
// Depth = 256, Width = 32
// This will be mapped to the actual SRAM macro during PnR
//-----------------------------------------------------------------------------
module fakeram45_256x32 (
    input  wire        clk,
    input  wire        ce_in,    // chip enable
    input  wire        we_in,    // write enable
    input  wire [7:0]  addr_in,  // 8-bit address (256 depth)
    input  wire [31:0] wd_in,    // write data
    input  wire [31:0] w_mask_in,// write mask
    output reg  [31:0] rd_out    // read data
);

    // Memory array
    reg [31:0] mem [0:255];
    
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'b0;
    end
    
    always @(posedge clk) begin
        if (ce_in) begin
            if (we_in) begin
                mem[addr_in] <= (wd_in & w_mask_in) | (mem[addr_in] & ~w_mask_in);
            end
            rd_out <= mem[addr_in];
        end
    end

endmodule
