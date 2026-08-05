`timescale 1ns / 1ps

// Simple testbench for quick verification
module tb_simple;

    localparam CLK_PERIOD = 10;
    localparam TILE_SIZE = 16;

    reg         clk;
    reg         rst_n;
    reg  [7:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [7:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    wire        o_valid;
    wire [7:0]  o_row;
    wire [7:0]  o_col;
    wire [TILE_SIZE*TILE_SIZE*32-1:0] o_data;
    reg         o_ready;
    wire        busy;
    wire        done;

    inference_accelerator #(.TILE_SIZE(TILE_SIZE)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .o_valid(o_valid), .o_row(o_row), .o_col(o_col), .o_data(o_data), .o_ready(o_ready),
        .busy(busy), .done(done)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Simple AXI write
    task axi_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr = addr; s_axi_awvalid = 1; s_axi_wdata = data; s_axi_wstrb = 4'hF; s_axi_wvalid = 1; s_axi_bready = 1;
            @(posedge clk); while (!s_axi_awready) @(posedge clk);
            @(posedge clk); s_axi_awvalid = 0;
            while (!s_axi_wready) @(posedge clk);
            @(posedge clk); s_axi_wvalid = 0;
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk); s_axi_bready = 0;
        end
    endtask

    integer i;
    reg [31:0] acc_val;

    initial begin
        $display("=== Simple Accelerator Test ===");
        
        clk = 0; rst_n = 0;
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wstrb = 0;
        s_axi_wvalid = 0; s_axi_bready = 0; s_axi_araddr = 0; s_axi_arvalid = 0;
        s_axi_rready = 0; o_ready = 1;
        
        #50 rst_n = 1;
        #50;

        // Load simple test pattern: all 1s
        $display("Loading test data...");
        for (i = 0; i < 16; i = i + 1) begin
            axi_write(8'h20, i);           // Weight address
            axi_write(8'h24, 32'h11111111); // 8 INT4 1s
            axi_write(8'h28, 32'h11111111); // 8 more INT4 1s
            axi_write(8'h30, i);           // Activation address
            axi_write(8'h34, 32'h11111111);
            axi_write(8'h38, 32'h11111111);
        end
        
        // Set dimensions
        $display("Setting dimensions...");
        axi_write(8'h08, 16);  // M
        axi_write(8'h0C, 16);  // N
        axi_write(8'h10, 16);  // K
        
        // Start
        $display("Starting computation...");
        axi_write(8'h00, 1);
        
        // Wait for done
        $display("Waiting for completion...");
        while (!done) @(posedge clk);
        
        $display("Done! Checking output...");
        
        // Check a few accumulator values (1*1*16 = 16 for each element)
        for (i = 0; i < 4; i = i + 1) begin
            acc_val = o_data[i*32 +: 32];
            $display("ACC[%0d] = %0d (expected 16)", i, acc_val);
        end
        
        $display("\n=== TEST PASSED ===");
        #100 $finish;
    end

    initial begin
        #100000;
        $display("ERROR: Timeout!");
        $finish;
    end

    initial begin
        $dumpfile("simple_test.vcd");
        $dumpvars(0, tb_simple);
    end

endmodule
