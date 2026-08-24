`timescale 1ns/1ps
module tb_x1_y1;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [11:0] k_dim = 0;
    wire act_req;
    wire [11:0] act_addr;
    reg [63:0] act_rdata;
    wire weight_req;
    wire [11:0] weight_addr;
    reg [63:0] weight_rdata;
    wire out_we;
    wire [13:0] out_addr;
    wire [23:0] out_wdata;
    wire busy;
    wire done;

    reg [63:0] act_mem [0:7];
    reg [63:0] weight_mem [0:7];
    integer expected [0:255];
    integer writes;
    integer r, c, k;
    integer av, wv;

    x1_y1_kimi dut (
        .clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
        .act_req(act_req), .act_addr(act_addr), .act_rdata(act_rdata),
        .weight_req(weight_req), .weight_addr(weight_addr),
        .weight_rdata(weight_rdata), .out_we(out_we), .out_addr(out_addr),
        .out_wdata(out_wdata), .busy(busy), .done(done)
    );

    always #5 clk = ~clk;

    // One-cycle synchronous SRAM models.
    always @(posedge clk) begin
        if (act_req) act_rdata <= act_mem[act_addr];
        if (weight_req) weight_rdata <= weight_mem[weight_addr];
    end

    always @(posedge clk) begin
        if (out_we) begin
            if ($signed(out_wdata) !== expected[out_addr]) begin
                $display("FAIL index=%0d got=%0d expected=%0d", out_addr,
                         $signed(out_wdata), expected[out_addr]);
                $fatal(1);
            end
            writes <= writes + 1;
        end
    end

    initial begin
        writes = 0;
        act_rdata = 0;
        weight_rdata = 0;
        for (r = 0; r < 256; r = r + 1) expected[r] = 0;
        for (k = 0; k < 7; k = k + 1) begin
            act_mem[k] = 0;
            weight_mem[k] = 0;
            for (r = 0; r < 16; r = r + 1) begin
                av = ((k * 3 + r * 5) % 16) - 8;
                act_mem[k][r*4 +: 4] = av[3:0];
            end
            for (c = 0; c < 16; c = c + 1) begin
                wv = ((k * 7 + c * 3) % 16) - 8;
                weight_mem[k][c*4 +: 4] = wv[3:0];
            end
        end
        for (r = 0; r < 16; r = r + 1)
            for (c = 0; c < 16; c = c + 1)
                for (k = 0; k < 7; k = k + 1) begin
                    av = $signed(act_mem[k][r*4 +: 4]);
                    wv = $signed(weight_mem[k][c*4 +: 4]);
                    expected[r*16+c] = expected[r*16+c] + av * wv;
                end

        repeat (3) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
        k_dim <= 7;
        start <= 1;
        @(posedge clk);
        start <= 0;
        wait(done);
        @(posedge clk);
        #1;
        if (writes != 256) begin
            $display("FAIL writes=%0d expected=256", writes);
            $fatal(1);
        end
        $display("PASS: 16x16 INT4 MAC, 7 K steps, 256 outputs verified");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL timeout");
        $fatal(1);
    end
endmodule
