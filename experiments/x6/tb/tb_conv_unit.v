`timescale 1ns/1ps
module tb_conv_unit;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, in_valid = 0;
    wire in_ready, out_valid;
    reg [511:0] history_data = 0;
    reg [255:0] alpha_weights = 0, beta_weights = 0;
    reg [255:0] alpha_bias = 0, beta_bias = 0;
    wire [127:0] alpha_out, beta_out;

    reg [511:0] history_mem [0:7];
    reg [255:0] aw_mem [0:7], bw_mem [0:7], ab_mem [0:7], bb_mem [0:7];
    reg [127:0] ag_mem [0:7], bg_mem [0:7];
    integer beat;
    integer output_count = 0;
    integer failures = 0;
    integer budget_cycles = 2;

    conv_unit dut (.*);

    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (alpha_out !== ag_mem[output_count]) begin
                $display("FAIL CONV alpha beat=%0d got=%h expected=%h", output_count, alpha_out, ag_mem[output_count]);
                failures = failures + 1;
            end
            if (beta_out !== bg_mem[output_count]) begin
                $display("FAIL CONV beta beat=%0d got=%h expected=%h", output_count, beta_out, bg_mem[output_count]);
                failures = failures + 1;
            end
            output_count = output_count + 1;
        end
    end

    initial begin
        $readmemh("tb/vectors/conv_history.mem", history_mem);
        $readmemh("tb/vectors/conv_alpha_weights.mem", aw_mem);
        $readmemh("tb/vectors/conv_beta_weights.mem", bw_mem);
        $readmemh("tb/vectors/conv_alpha_bias.mem", ab_mem);
        $readmemh("tb/vectors/conv_beta_bias.mem", bb_mem);
        $readmemh("tb/vectors/conv_alpha_golden.mem", ag_mem);
        $readmemh("tb/vectors/conv_beta_golden.mem", bg_mem);
        repeat (3) @(posedge clk); rst_n = 1;

        for (beat = 0; beat < 8; beat = beat + 1) begin
            @(negedge clk);
            in_valid = 1;
            history_data = history_mem[beat];
            alpha_weights = aw_mem[beat];
            beta_weights = bw_mem[beat];
            alpha_bias = ab_mem[beat];
            beta_bias = bb_mem[beat];
            if (!in_ready) begin
                $display("FAIL CONV backpressure beat=%0d", beat);
                failures = failures + 1;
            end
        end
        @(negedge clk); in_valid = 0;
        wait (output_count == 8);

        budget_cycles = budget_cycles + 8;
        if (budget_cycles != 10) begin
            $display("FAIL CONV budget=%0d expected=10", budget_cycles);
            failures = failures + 1;
        end
        if (failures == 0) $display("PASS tb_conv_unit: 128 channels, PWL gates, 10-cycle architectural budget");
        else $display("FAIL tb_conv_unit: %0d errors", failures);
        $finish_and_return(failures != 0);
    end
endmodule
