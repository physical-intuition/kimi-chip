`timescale 1ns/1ps
module tb_state_update;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, start = 0, pass_select = 0, row_valid = 0;
    wire row_ready;
    reg [6:0] row_index = 0;
    reg [3071:0] state_row_in = 0;
    reg signed [7:0] alpha_scalar = 0, k_scalar = 0, q_scalar = 0;
    reg [3071:0] delta_vector = 0;
    wire row_out_valid, done;
    wire [6:0] row_out_index;
    wire [3071:0] state_row_out, reduction_vector;

    reg [3071:0] state_rows [0:127];
    reg [3071:0] scaled_rows [0:127];
    reg [3071:0] updated_rows [0:127];
    reg [7:0] alpha_mem [0:127], k_mem [0:127], q_mem [0:127];
    reg [3071:0] delta_mem [0:0], u_mem [0:0], qout_mem [0:0];
    integer i;
    integer failures = 0;
    integer accepted_rows = 0;
    integer output_rows = 0;
    reg monitor_pass = 0;

    state_update dut (.*);

    always @(negedge clk) begin
        if (rst_n && row_out_valid) begin
            if (row_out_index !== output_rows[6:0]) begin
                $display("FAIL STATE output index got=%0d expected=%0d", row_out_index, output_rows);
                failures = failures + 1;
            end
            if (!monitor_pass && state_row_out !== scaled_rows[output_rows]) begin
                $display("FAIL STATE scale row=%0d", output_rows);
                failures = failures + 1;
            end
            if (monitor_pass && state_row_out !== updated_rows[output_rows]) begin
                $display("FAIL STATE update row=%0d", output_rows);
                failures = failures + 1;
            end
            output_rows = output_rows + 1;
        end
    end

    task run_pass;
        input reg which_pass;
        begin
            monitor_pass = which_pass;
            output_rows = 0;
            @(negedge clk); start = 1; pass_select = which_pass;
            @(negedge clk); start = 0;
            for (i = 0; i < 128; i = i + 1) begin
                wait (row_ready);
                @(negedge clk);
                row_valid = 1;
                row_index = i[6:0];
                state_row_in = which_pass ? scaled_rows[i] : state_rows[i];
                alpha_scalar = alpha_mem[i];
                k_scalar = k_mem[i];
                q_scalar = q_mem[i];
                accepted_rows = accepted_rows + 1;
                @(negedge clk);
                row_valid = 0;
            end
            wait (done === 1'b1);
            @(negedge clk); #1;
            if (output_rows != 128) begin
                $display("FAIL STATE pass=%0d output rows=%0d", which_pass, output_rows);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        $readmemh("tb/vectors/state_rows.mem", state_rows);
        $readmemh("tb/vectors/state_scaled.mem", scaled_rows);
        $readmemh("tb/vectors/state_updated.mem", updated_rows);
        $readmemh("tb/vectors/state_alpha.mem", alpha_mem);
        $readmemh("tb/vectors/state_k.mem", k_mem);
        $readmemh("tb/vectors/state_q.mem", q_mem);
        $readmemh("tb/vectors/state_delta.mem", delta_mem);
        $readmemh("tb/vectors/state_u.mem", u_mem);
        $readmemh("tb/vectors/state_qout.mem", qout_mem);
        delta_vector = delta_mem[0];
        repeat (3) @(posedge clk); rst_n = 1;

        run_pass(1'b0);
        if (reduction_vector !== u_mem[0]) begin
            $display("FAIL STATE pass-1 reduction mismatch");
            failures = failures + 1;
        end

        // The controller's d=beta(v-u) vector stage owns exactly two budget cycles.
        repeat (2) @(posedge clk);
        run_pass(1'b1);
        if (reduction_vector !== qout_mem[0]) begin
            $display("FAIL STATE pass-2 reduction mismatch");
            failures = failures + 1;
        end

        if (accepted_rows + 2 != 258) begin
            $display("FAIL STATE architectural budget got=%0d expected=258", accepted_rows + 2);
            failures = failures + 1;
        end
        if (failures == 0) $display("PASS tb_state_update: recurrence values and 128+2+128=258 budget cycles");
        else $display("FAIL tb_state_update: %0d errors", failures);
        $finish_and_return(failures != 0);
    end
endmodule
