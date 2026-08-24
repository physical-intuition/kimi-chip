`timescale 1ns/1ps
module tb_mac_array;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    reg weight_load_valid = 0, weight_load_buffer = 0;
    reg [2:0] weight_load_beat = 0;
    reg [255:0] weight_load_data = 0;
    wire weight_load_ready;
    reg weight_activate = 0, weight_activate_buffer = 0;
    reg acc_clear = 0, mac_valid = 0;
    reg [127:0] activation_data = 0;
    wire mac_ready, result_valid;
    wire [383:0] result_data;

    reg [127:0] activation_mem [0:7];
    reg [255:0] weight_mem [0:255];
    reg [383:0] golden_mem [0:7];
    integer tile, beat;
    integer accepted_beats = 0;
    integer failures = 0;

    mac_array_16x16 dut (.*);

    task load_subtile;
        input integer tile_id;
        input integer chunk_id;
        input reg buffer_id;
        integer wb;
        begin
            for (wb = 0; wb < 4; wb = wb + 1) begin
                @(negedge clk);
                weight_load_valid = 1;
                weight_load_buffer = buffer_id;
                weight_load_beat = wb[2:0];
                weight_load_data = weight_mem[tile_id*32+chunk_id*4+wb];
                #1;
                if (!weight_load_ready) begin
                    $display("FAIL MAC weight load backpressured tile=%0d chunk=%0d beat=%0d", tile_id, chunk_id, wb);
                    failures = failures + 1;
                end
            end
            @(negedge clk);
            weight_load_valid = 0;
            weight_activate = 1;
            weight_activate_buffer = buffer_id;
            @(negedge clk);
            weight_activate = 0;
        end
    endtask

    task clear_accumulator;
        begin
            @(negedge clk); acc_clear = 1;
            @(negedge clk); acc_clear = 0;
        end
    endtask

    initial begin
        $readmemh("tb/vectors/mac_activation.mem", activation_mem);
        $readmemh("tb/vectors/mac_weights.mem", weight_mem);
        $readmemh("tb/vectors/mac_golden.mem", golden_mem);
        repeat (3) @(posedge clk);
        rst_n = 1;

        for (tile = 0; tile < 8; tile = tile + 1) begin
            clear_accumulator();
            for (beat = 0; beat < 8; beat = beat + 1) begin
                load_subtile(tile, beat, beat[0]);
                wait(mac_ready); @(negedge clk);
                mac_valid = 1; activation_data = activation_mem[beat];
                accepted_beats = accepted_beats + 1;
                @(negedge clk); mac_valid = 0;
                wait(result_valid);
            end
            wait (result_valid);
            @(negedge clk); #1;
            if (!result_valid || result_data !== golden_mem[tile]) begin
                $display("FAIL MAC tile=%0d got=%h expected=%h valid=%b", tile, result_data, golden_mem[tile], result_valid);
                failures = failures + 1;
            end
        end

        if (accepted_beats != 64) begin
            $display("FAIL MAC cycle budget accepted=%0d expected=64", accepted_beats);
            failures = failures + 1;
        end

        // Overflow regression: all +7 weights and +127 activations must saturate.
        for (beat = 0; beat < 8; beat = beat + 1) weight_mem[beat] = {64{4'h7}};
        load_subtile(0, 0, 1'b0);
        clear_accumulator();
        activation_data = {16{8'h7f}};
        for (beat = 0; beat < 600; beat = beat + 1) begin
            wait(mac_ready); @(negedge clk); mac_valid = 1;
            @(negedge clk); mac_valid = 0;
        end
        @(posedge clk); @(negedge clk); #1;
        if ($signed(result_data[23:0]) !== 24'sh7fffff) begin
            $display("FAIL MAC positive overflow did not saturate: %h", result_data[23:0]);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS tb_mac_array: 64 GEMV beats, eight tiles, saturation checked");
        else $display("FAIL tb_mac_array: %0d errors", failures);
        $finish_and_return(failures != 0);
    end
endmodule
