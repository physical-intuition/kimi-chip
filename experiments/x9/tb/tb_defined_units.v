`timescale 1ns/1ps
module tb_defined_units;
    reg signed [23:0] acc;
    wire signed [7:0] rq;
    reg [1:0] matrix;
    reg [6:0] row, col;
    wire [2:0] bank;
    wire [7:0] addr, word;
    wire [5:0] lane;
    reg row_valid;
    wire mac0_valid, mac1_valid;
    wire [5:0] local_row;
    integer failures, r, c, expected_word, expected_bank, expected_addr;

    requant_24_to_8 u_rq(.acc(acc), .out(rq));
    weight_addr_gen u_addr(.matrix(matrix), .row(row), .col(col),
        .bank(bank), .addr(addr), .lane(lane), .word(word));
    mac_scheduler u_sched(.row_valid(row_valid), .row(row),
        .mac0_valid(mac0_valid), .mac1_valid(mac1_valid), .local_row(local_row));

    task check_rq;
        input signed [23:0] value;
        input signed [7:0] expected;
        begin
            acc = value; #1;
            if (rq !== expected) begin
                $display("FAIL requant acc=%0d got=%0d expected=%0d", value, rq, expected);
                failures = failures + 1;
            end
            if ((rq > 127) || (rq < -128)) begin
                $display("FAIL requant range acc=%0d got=%0d", value, rq);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        acc = 0; matrix = 0; row = 0; col = 0; row_valid = 0;
        check_rq(24'sd0, 8'sd0);
        check_rq(24'sd255, 8'sd0);
        check_rq(24'sd256, 8'sd1);
        check_rq(-24'sd256, -8'sd1);
        check_rq(24'sd32512, 8'sd127);
        check_rq(24'sd32768, 8'sd127);
        check_rq(-24'sd32768, -8'sd128);
        check_rq(-24'sd32769, -8'sd128);
        check_rq(24'sh7fffff, 8'sd127);
        check_rq(-24'sd8388608, -8'sd128);

        matrix = 0;
        for (r = 0; r < 128; r = r + 1) begin
            for (c = 0; c < 128; c = c + 1) begin
                row = r; col = c; #1;
                expected_word = (r * 128 + c) / 64;
                expected_bank = expected_word % 6;
                expected_addr = expected_word / 6;
                if ((word !== expected_word[7:0]) || (bank !== expected_bank[2:0]) ||
                    (addr !== expected_addr[7:0]) || (lane !== c[5:0])) begin
                    $display("FAIL addr r=%0d c=%0d word=%0d bank=%0d addr=%0d lane=%0d",
                        r, c, word, bank, addr, lane);
                    failures = failures + 1;
                end
            end
        end

        row = 127; col = 127;
        matrix = 1; #1; if (addr !== 8'd85 || bank !== 3'd3) failures = failures + 1;
        matrix = 2; #1; if (addr !== 8'd128 || bank !== 3'd3) failures = failures + 1;
        matrix = 3; #1; if (addr !== 8'd171 || bank !== 3'd3) failures = failures + 1;

        row_valid = 1; row = 63; #1;
        if (!mac0_valid || mac1_valid || local_row !== 63) failures = failures + 1;
        row = 64; #1;
        if (mac0_valid || !mac1_valid || local_row !== 0) failures = failures + 1;
        row_valid = 0; #1;
        if (mac0_valid || mac1_valid) failures = failures + 1;

        if (failures == 0)
            $display("PASS X9 defined units: requant, all 16384 K addresses, matrix bases, row split");
        else
            $display("FAIL X9 defined units failures=%0d", failures);
        $finish_and_return(failures != 0);
    end
endmodule
