`timescale 1ns/1ps
module tb_norm_unit;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, start = 0, in_valid = 0, out_ready = 1;
    wire in_ready, out_valid, done;
    reg [383:0] in_data = 0;
    wire [127:0] out_data;
    reg [383:0] input_mem [0:7];
    reg [127:0] golden_mem [0:7];
    integer beat;
    integer output_count = 0;
    integer failures = 0;
    integer collect_cycles = 0, refine_cycles = 0, emit_cycles = 0;

    norm_unit dut (.*);

    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (out_data !== golden_mem[output_count]) begin
                $display("FAIL NORM beat=%0d got=%h expected=%h", output_count, out_data, golden_mem[output_count]);
                failures = failures + 1;
            end
            output_count = output_count + 1;
            emit_cycles = emit_cycles + 1;
        end
    end

    initial begin
        $readmemh("tb/vectors/norm_input.mem", input_mem);
        $readmemh("tb/vectors/norm_golden.mem", golden_mem);
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        for (beat = 0; beat < 8; beat = beat + 1) begin
            in_valid = 1;
            in_data = input_mem[beat];
            if (!in_ready) begin
                $display("FAIL NORM not ready beat=%0d", beat);
                failures = failures + 1;
            end else collect_cycles = collect_cycles + 1;
            @(negedge clk);
        end
        in_valid = 0;

        // REFINE is an explicit fixed eight-cycle registered phase.
        repeat (8) begin @(posedge clk); refine_cycles = refine_cycles + 1; end
        wait (output_count == 8);

        if (collect_cycles + refine_cycles + emit_cycles != 24) begin
            $display("FAIL NORM budget collect=%0d refine=%0d emit=%0d", collect_cycles, refine_cycles, emit_cycles);
            failures = failures + 1;
        end
        if (!done && output_count != 8) begin
            $display("FAIL NORM completion protocol");
            failures = failures + 1;
        end
        if (failures == 0) $display("PASS tb_norm_unit: fixed-point RMSNorm and 8+8+8=24 budget cycles");
        else $display("FAIL tb_norm_unit: %0d errors", failures);
        $finish_and_return(failures != 0);
    end
endmodule
