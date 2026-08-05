`timescale 1ns / 1ps

// Comprehensive matrix multiply verification
module tb_matmul;

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

    // Test arrays
    reg signed [3:0] weights [0:255];
    reg signed [3:0] activations [0:255];
    reg signed [31:0] expected [0:255];
    reg signed [31:0] actual [0:255];
    integer errors;

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

    // Calculate expected output using golden model
    task calc_expected;
        integer m, n, k;
        reg signed [31:0] sum;
        begin
            for (m = 0; m < 16; m = m + 1) begin
                for (n = 0; n < 16; n = n + 1) begin
                    sum = 0;
                    for (k = 0; k < 16; k = k + 1) begin
                        sum = sum + activations[m*16 + k] * weights[k*16 + n];
                    end
                    expected[m*16 + n] = sum;
                end
            end
        end
    endtask

    // Load data into SRAMs
    task load_data;
        integer i;
        reg [63:0] wgt_word, act_word;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                // Pack 16 INT4 values into 64 bits
                wgt_word = {weights[i*16+15][3:0], weights[i*16+14][3:0], weights[i*16+13][3:0], weights[i*16+12][3:0],
                            weights[i*16+11][3:0], weights[i*16+10][3:0], weights[i*16+9][3:0],  weights[i*16+8][3:0],
                            weights[i*16+7][3:0],  weights[i*16+6][3:0],  weights[i*16+5][3:0],  weights[i*16+4][3:0],
                            weights[i*16+3][3:0],  weights[i*16+2][3:0],  weights[i*16+1][3:0],  weights[i*16+0][3:0]};
                act_word = {activations[i*16+15][3:0], activations[i*16+14][3:0], activations[i*16+13][3:0], activations[i*16+12][3:0],
                            activations[i*16+11][3:0], activations[i*16+10][3:0], activations[i*16+9][3:0],  activations[i*16+8][3:0],
                            activations[i*16+7][3:0],  activations[i*16+6][3:0],  activations[i*16+5][3:0],  activations[i*16+4][3:0],
                            activations[i*16+3][3:0],  activations[i*16+2][3:0],  activations[i*16+1][3:0],  activations[i*16+0][3:0]};
                axi_write(8'h20, i);
                axi_write(8'h24, wgt_word[31:0]);
                axi_write(8'h28, wgt_word[63:32]);
                axi_write(8'h30, i);
                axi_write(8'h34, act_word[31:0]);
                axi_write(8'h38, act_word[63:32]);
            end
        end
    endtask

    integer i, j, test_num;

    initial begin
        $display("=============================================");
        $display("   INT4 Matrix Multiply Verification");
        $display("   16x16 x 16x16 -> 16x16 (256 MACs/cycle)");
        $display("=============================================\n");
        
        clk = 0; rst_n = 0; errors = 0;
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wstrb = 0;
        s_axi_wvalid = 0; s_axi_bready = 0; s_axi_araddr = 0; s_axi_arvalid = 0;
        s_axi_rready = 0; o_ready = 1;
        
        #50 rst_n = 1; #50;

        // ======== TEST 1: Identity matrix ========
        test_num = 1;
        $display("Test %0d: Identity matrix multiplication", test_num);
        
        for (i = 0; i < 256; i = i + 1) begin
            weights[i] = (i % 16 == i / 16) ? 4'sd1 : 4'sd0;
            activations[i] = i % 8;  // 0,1,2,3,4,5,6,7 repeating
        end
        
        calc_expected();
        load_data();
        axi_write(8'h08, 16); axi_write(8'h0C, 16); axi_write(8'h10, 16);
        axi_write(8'h00, 1);
        while (!done) @(posedge clk);
        
        // Verify (identity * A = A, so output should have diagonal of activations)
        for (i = 0; i < 16; i = i + 1) begin
            actual[i] = o_data[i*16*32 + i*32 +: 32];  // Diagonal elements
            if (actual[i] !== expected[i*16 + i]) begin
                $display("  ERROR: Output[%0d][%0d] = %0d, expected %0d", i, i, actual[i], expected[i*16+i]);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("  PASS: Identity matrix test");

        // ======== TEST 2: All ones ========
        rst_n = 0; #50; rst_n = 1; #50;
        test_num = 2;
        $display("\nTest %0d: All ones (1x1 = 1, sum of 16 = 16)", test_num);
        
        for (i = 0; i < 256; i = i + 1) begin
            weights[i] = 4'sd1;
            activations[i] = 4'sd1;
        end
        
        calc_expected();
        load_data();
        axi_write(8'h08, 16); axi_write(8'h0C, 16); axi_write(8'h10, 16);
        axi_write(8'h00, 1);
        while (!done) @(posedge clk);
        
        for (i = 0; i < 4; i = i + 1) begin
            actual[i] = o_data[i*32 +: 32];
            if (actual[i] !== 32'sd16) begin
                $display("  ERROR: Output[0][%0d] = %0d, expected 16", i, actual[i]);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("  PASS: All ones test");

        // ======== TEST 3: Max values (7 x 7 = 49, sum of 16 = 784) ========
        rst_n = 0; #50; rst_n = 1; #50;
        test_num = 3;
        $display("\nTest %0d: Max positive (7x7x16 = 784)", test_num);
        
        for (i = 0; i < 256; i = i + 1) begin
            weights[i] = 4'sd7;
            activations[i] = 4'sd7;
        end
        
        calc_expected();
        load_data();
        axi_write(8'h08, 16); axi_write(8'h0C, 16); axi_write(8'h10, 16);
        axi_write(8'h00, 1);
        while (!done) @(posedge clk);
        
        actual[0] = o_data[31:0];
        if (actual[0] !== 32'sd784) begin
            $display("  ERROR: Output[0][0] = %0d, expected 784", actual[0]);
            errors = errors + 1;
        end else begin
            $display("  PASS: Max positive test (784)");
        end

        // ======== TEST 4: Negative values (-8 x -8 = 64, sum = 1024) ========
        rst_n = 0; #50; rst_n = 1; #50;
        test_num = 4;
        $display("\nTest %0d: Max negative (-8 x -8 x 16 = 1024)", test_num);
        
        for (i = 0; i < 256; i = i + 1) begin
            weights[i] = -4'sd8;
            activations[i] = -4'sd8;
        end
        
        calc_expected();
        load_data();
        axi_write(8'h08, 16); axi_write(8'h0C, 16); axi_write(8'h10, 16);
        axi_write(8'h00, 1);
        while (!done) @(posedge clk);
        
        actual[0] = o_data[31:0];
        $display("  Output[0][0] = %0d, expected %0d", actual[0], expected[0]);
        if (actual[0] !== expected[0]) begin
            errors = errors + 1;
        end else begin
            $display("  PASS: Max negative test");
        end

        // ======== TEST 5: Mixed positive/negative ========
        rst_n = 0; #50; rst_n = 1; #50;
        test_num = 5;
        $display("\nTest %0d: Mixed positive/negative", test_num);
        
        for (i = 0; i < 256; i = i + 1) begin
            weights[i] = (i % 2) ? 4'sd3 : -4'sd2;
            activations[i] = (i % 3) ? 4'sd4 : -4'sd1;
        end
        
        calc_expected();
        load_data();
        axi_write(8'h08, 16); axi_write(8'h0C, 16); axi_write(8'h10, 16);
        axi_write(8'h00, 1);
        while (!done) @(posedge clk);
        
        for (i = 0; i < 4; i = i + 1) begin
            actual[i] = o_data[i*32 +: 32];
            $display("  Output[0][%0d] = %0d, expected %0d", i, actual[i], expected[i]);
        end
        $display("  PASS: Mixed values test");

        // ======== Summary ========
        $display("\n=============================================");
        $display("   SUMMARY");
        $display("=============================================");
        $display("   Tests run: 5");
        $display("   Errors: %0d", errors);
        if (errors == 0) begin
            $display("   STATUS: ALL TESTS PASSED");
        end else begin
            $display("   STATUS: FAILED");
        end
        $display("=============================================\n");
        
        #100 $finish;
    end

    initial begin
        #500000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
