`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Testbench for Audit Top-Level
//-----------------------------------------------------------------------------
module tb_audit_top;

    reg clk;
    reg rst_n;
    reg token_valid;
    wire token_ready;
    reg [8:0] token_id;
    reg seq_start;
    wire output_valid;
    wire [512*32-1:0] logits;
    wire [8:0] argmax_id;
    
    // Clock generation: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;
    
    // DUT instantiation
    audit_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .token_valid(token_valid),
        .token_ready(token_ready),
        .token_id(token_id),
        .seq_start(seq_start),
        .output_valid(output_valid),
        .logits(logits),
        .argmax_id(argmax_id)
    );
    
    // Test sequence
    integer i;
    initial begin
        $dumpfile("tb_audit_top.vcd");
        $dumpvars(0, tb_audit_top);
        
        // Reset
        rst_n = 0;
        token_valid = 0;
        token_id = 0;
        seq_start = 0;
        #100;
        rst_n = 1;
        #20;
        
        // Start new sequence
        @(posedge clk);
        seq_start = 1;
        @(posedge clk);
        seq_start = 0;
        #100;
        
        // Feed tokens
        for (i = 0; i < 8; i = i + 1) begin
            wait(token_ready);
            @(posedge clk);
            token_valid = 1;
            token_id = i;
            @(posedge clk);
            token_valid = 0;
            
            // Wait for output
            wait(output_valid);
            $display("Token %d -> argmax %d", i, argmax_id);
            @(posedge clk);
        end
        
        #1000;
        $display("Test complete");
        $finish;
    end
    
    // Timeout
    initial begin
        #1000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
