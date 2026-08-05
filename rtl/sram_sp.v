// Single-port SRAM (synthesizable with registers)
// For weight/activation storage
module sram_sp #(
    parameter DEPTH = 4096,    // Number of entries
    parameter WIDTH = 64,      // Data width
    parameter ADDR_W = $clog2(DEPTH)
)(
    input  wire              clk,
    input  wire              cs,       // Chip select
    input  wire              we,       // Write enable
    input  wire [ADDR_W-1:0] addr,
    input  wire [WIDTH-1:0]  wdata,
    output reg  [WIDTH-1:0]  rdata
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (cs) begin
            if (we) begin
                mem[addr] <= wdata;
            end
            rdata <= mem[addr];
        end
    end

endmodule
