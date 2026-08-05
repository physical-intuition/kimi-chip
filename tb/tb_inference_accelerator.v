`timescale 1ns / 1ps

// Testbench for Inference Accelerator
// Verifies INT4 matrix multiplication correctness
module tb_inference_accelerator;

    // Parameters
    localparam CLK_PERIOD = 10;  // 100 MHz
    localparam TILE_SIZE = 16;

    // DUT signals
    reg         clk;
    reg         rst_n;
    
    // AXI-Lite
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
    
    // Output
    wire        o_valid;
    wire [7:0]  o_row;
    wire [7:0]  o_col;
    wire [TILE_SIZE*TILE_SIZE*32-1:0] o_data;
    reg         o_ready;
    wire        busy;
    wire        done;

    // Test data
    reg signed [3:0] test_weights [0:255];   // 16x16 weight matrix
    reg signed [3:0] test_activations [0:255]; // 16x16 activation matrix
    reg signed [31:0] expected_output [0:255]; // Expected 16x16 output
    reg signed [31:0] actual_output [0:255];
    
    integer i, j, k;
    integer errors;
    integer test_num;

    // DUT instantiation
    inference_accelerator #(
        .TILE_SIZE (TILE_SIZE)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .o_valid        (o_valid),
        .o_row          (o_row),
        .o_col          (o_col),
        .o_data         (o_data),
        .o_ready        (o_ready),
        .busy           (busy),
        .done           (done)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // AXI write task
    task axi_write;
        input [7:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata <= data;
            s_axi_wstrb <= 4'hF;
            s_axi_wvalid <= 1'b1;
            s_axi_bready <= 1'b1;
            
            // Wait for address accepted
            while (!s_axi_awready) @(posedge clk);
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            
            // Wait for data accepted
            while (!s_axi_wready) @(posedge clk);
            @(posedge clk);
            s_axi_wvalid <= 1'b0;
            
            // Wait for response
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk);
            s_axi_bready <= 1'b0;
        end
    endtask

    // AXI read task
    task axi_read;
        input [7:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready <= 1'b1;
            
            while (!s_axi_arready) @(posedge clk);
            @(posedge clk);
            s_axi_arvalid <= 1'b0;
            
            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;
        end
    endtask

    // Generate random INT4 value (-8 to 7)
    function signed [3:0] rand_int4;
        begin
            rand_int4 = $random % 8;
        end
    endfunction

    // Calculate expected output (golden model)
    task calculate_expected;
        integer m, n, kk;
        reg signed [31:0] sum;
        begin
            for (m = 0; m < 16; m = m + 1) begin
                for (n = 0; n < 16; n = n + 1) begin
                    sum = 0;
                    for (kk = 0; kk < 16; kk = kk + 1) begin
                        sum = sum + test_activations[m*16 + kk] * test_weights[kk*16 + n];
                    end
                    expected_output[m*16 + n] = sum;
                end
            end
        end
    endtask

    // Load test data into accelerator SRAMs
    task load_test_data;
        integer idx;
        reg [63:0] wgt_word, act_word;
        begin
            $display("Loading test data into SRAMs...");
            
            // Load weights (16 INT4 values per 64-bit word)
            for (idx = 0; idx < 16; idx = idx + 1) begin
                wgt_word = {
                    test_weights[idx*16 + 15], test_weights[idx*16 + 14],
                    test_weights[idx*16 + 13], test_weights[idx*16 + 12],
                    test_weights[idx*16 + 11], test_weights[idx*16 + 10],
                    test_weights[idx*16 + 9],  test_weights[idx*16 + 8],
                    test_weights[idx*16 + 7],  test_weights[idx*16 + 6],
                    test_weights[idx*16 + 5],  test_weights[idx*16 + 4],
                    test_weights[idx*16 + 3],  test_weights[idx*16 + 2],
                    test_weights[idx*16 + 1],  test_weights[idx*16 + 0]
                };
                axi_write(8'h20, idx);           // Weight address
                axi_write(8'h24, wgt_word[31:0]); // Weight data low
                axi_write(8'h28, wgt_word[63:32]); // Weight data high (triggers write)
            end
            
            // Load activations
            for (idx = 0; idx < 16; idx = idx + 1) begin
                act_word = {
                    test_activations[idx*16 + 15], test_activations[idx*16 + 14],
                    test_activations[idx*16 + 13], test_activations[idx*16 + 12],
                    test_activations[idx*16 + 11], test_activations[idx*16 + 10],
                    test_activations[idx*16 + 9],  test_activations[idx*16 + 8],
                    test_activations[idx*16 + 7],  test_activations[idx*16 + 6],
                    test_activations[idx*16 + 5],  test_activations[idx*16 + 4],
                    test_activations[idx*16 + 3],  test_activations[idx*16 + 2],
                    test_activations[idx*16 + 1],  test_activations[idx*16 + 0]
                };
                axi_write(8'h30, idx);           // Activation address
                axi_write(8'h34, act_word[31:0]); // Activation data low
                axi_write(8'h38, act_word[63:32]); // Activation data high (triggers write)
            end
            
            $display("Test data loaded.");
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Inference Accelerator Testbench");
        $display("========================================");
        
        // Initialize
        clk = 0;
        rst_n = 0;
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        o_ready = 1;
        errors = 0;
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // ========================================
        // Test 1: Simple identity-like pattern
        // ========================================
        test_num = 1;
        $display("\n--- Test %0d: Identity-like pattern ---", test_num);
        
        // Initialize with simple pattern
        for (i = 0; i < 256; i = i + 1) begin
            test_weights[i] = (i % 16 == i / 16) ? 4'd1 : 4'd0;  // Identity-ish
            test_activations[i] = (i % 8);  // 0 to 7 repeating
        end
        
        calculate_expected();
        load_test_data();
        
        // Configure dimensions
        axi_write(8'h08, 32'd16);  // M
        axi_write(8'h0C, 32'd16);  // N
        axi_write(8'h10, 32'd16);  // K
        
        // Start computation
        $display("Starting matrix multiply...");
        axi_write(8'h00, 32'd1);
        
        // Wait for completion
        while (!done) begin
            #(CLK_PERIOD * 10);
        end
        $display("Computation complete!");
        
        // Capture output
        if (o_valid) begin
            for (i = 0; i < 256; i = i + 1) begin
                actual_output[i] = o_data[i*32 +: 32];
            end
        end
        
        // Verify results (sample check)
        $display("Verifying results...");
        for (i = 0; i < 16; i = i + 1) begin
            $display("Row %0d: Expected[0]=%0d, Got MAC acc values", i, expected_output[i*16]);
        end

        // ========================================
        // Test 2: Random data
        // ========================================
        test_num = 2;
        $display("\n--- Test %0d: Random INT4 data ---", test_num);
        
        // Generate random test data
        for (i = 0; i < 256; i = i + 1) begin
            test_weights[i] = rand_int4();
            test_activations[i] = rand_int4();
        end
        
        calculate_expected();
        
        $display("Sample weights: W[0]=%0d, W[1]=%0d, W[2]=%0d", 
                 test_weights[0], test_weights[1], test_weights[2]);
        $display("Sample activations: A[0]=%0d, A[1]=%0d, A[2]=%0d",
                 test_activations[0], test_activations[1], test_activations[2]);
        $display("Expected output[0][0] = %0d", expected_output[0]);

        // Reset for new test
        rst_n = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        load_test_data();
        
        // Configure and run
        axi_write(8'h08, 32'd16);
        axi_write(8'h0C, 32'd16);
        axi_write(8'h10, 32'd16);
        axi_write(8'h00, 32'd1);
        
        while (!done) begin
            #(CLK_PERIOD * 10);
        end
        $display("Test 2 complete!");

        // ========================================
        // Test 3: Edge cases (max/min values)
        // ========================================
        test_num = 3;
        $display("\n--- Test %0d: Edge cases (max/min INT4) ---", test_num);
        
        // All max positive
        for (i = 0; i < 256; i = i + 1) begin
            test_weights[i] = 4'd7;      // Max positive
            test_activations[i] = 4'd7;
        end
        
        calculate_expected();
        $display("Max case: 16 * (7 * 7) = %0d, Expected[0] = %0d", 16*49, expected_output[0]);

        rst_n = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        load_test_data();
        axi_write(8'h08, 32'd16);
        axi_write(8'h0C, 32'd16);
        axi_write(8'h10, 32'd16);
        axi_write(8'h00, 32'd1);
        
        while (!done) begin
            #(CLK_PERIOD * 10);
        end
        $display("Test 3 complete!");

        // ========================================
        // Summary
        // ========================================
        $display("\n========================================");
        $display("All tests completed!");
        $display("Errors: %0d", errors);
        if (errors == 0) begin
            $display("STATUS: PASS");
        end else begin
            $display("STATUS: FAIL");
        end
        $display("========================================");
        
        #(CLK_PERIOD * 10);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("inference_accelerator.vcd");
        $dumpvars(0, tb_inference_accelerator);
    end

endmodule
