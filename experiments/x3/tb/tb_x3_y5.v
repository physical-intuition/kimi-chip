`timescale 1ns/1ps
module tb_x3_y5;
    reg clk = 0, rst_n = 0, start = 0;
    reg [11:0] k_dim = 0;
    wire act_req, weight_req, out_we, busy, done;
    wire [11:0] act_addr, weight_addr;
    wire [13:0] out_addr;
    wire [23:0] out_wdata;
    reg [63:0] act_rdata, weight_rdata;
    reg [63:0] act_mem [0:15];
    reg [63:0] weight_mem [0:15];
    reg seen [0:255];
    integer expected [0:255];
    integer writes, r, c, k, av, wv;
    reg collecting;

    x3_y5_kimi dut (
        .clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
        .act_req(act_req), .act_addr(act_addr), .act_rdata(act_rdata),
        .weight_req(weight_req), .weight_addr(weight_addr), .weight_rdata(weight_rdata),
        .out_we(out_we), .out_addr(out_addr), .out_wdata(out_wdata), .busy(busy), .done(done)
    );
    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (act_req !== weight_req) begin $display("FAIL unpaired memory request"); $fatal(1); end
        if (act_req) begin act_rdata <= act_mem[act_addr]; weight_rdata <= weight_mem[weight_addr]; end
    end
    always @(posedge clk) if (out_we) begin
        if (!collecting) begin $display("FAIL stale write outside accepted transaction"); $fatal(1); end
        if (out_addr >= 256) begin $display("FAIL out-of-range address %0d", out_addr); $fatal(1); end
        if (seen[out_addr]) begin $display("FAIL duplicate address %0d", out_addr); $fatal(1); end
        seen[out_addr] <= 1;
        if ($signed(out_wdata) !== expected[out_addr]) begin
            $display("FAIL index=%0d got=%0d expected=%0d", out_addr, $signed(out_wdata), expected[out_addr]);
            $fatal(1);
        end
        writes <= writes + 1;
    end
    task run_case;
        input integer count;
        begin
            writes = 0;
            for (r = 0; r < 256; r = r + 1) begin expected[r] = 0; seen[r] = 0; end
            for (r = 0; r < 16; r = r + 1)
                for (c = 0; c < 16; c = c + 1)
                    for (k = 0; k < count; k = k + 1) begin
                        av = $signed(act_mem[k][r*4 +: 4]);
                        wv = $signed(weight_mem[k][c*4 +: 4]);
                        expected[r*16+c] = expected[r*16+c] + av * wv;
                    end
            collecting = 1;
            @(posedge clk); k_dim <= count; start <= 1;
            @(posedge clk); start <= 0; k_dim <= 12'hA55;
            wait(done); @(posedge clk); #1;
            collecting = 0;
            if (writes != 256) begin $display("FAIL writes=%0d expected=256 k=%0d", writes, count); $fatal(1); end
            for (r = 0; r < 256; r = r + 1) if (!seen[r]) begin $display("FAIL missing address %0d", r); $fatal(1); end
        end
    endtask
    task abort_midrun;
        begin
            collecting = 0;
            @(posedge clk); k_dim <= 12'd13; start <= 1;
            @(posedge clk); start <= 0;
            repeat (4) @(posedge clk);
            if (!busy) begin $display("FAIL abort stimulus never became busy"); $fatal(1); end
            @(negedge clk); rst_n <= 0;
            repeat (2) @(posedge clk);
            if (busy || act_req || weight_req || out_we || done) begin $display("FAIL reset did not quiesce transaction"); $fatal(1); end
            @(negedge clk); rst_n <= 1;
            repeat (3) @(posedge clk);
            if (busy || act_req || weight_req || out_we || done) begin $display("FAIL stale activity after reset release"); $fatal(1); end
        end
    endtask
    initial begin
        writes = 0; collecting = 0; act_rdata = 0; weight_rdata = 0;
        for (k = 0; k < 16; k = k + 1) begin
            act_mem[k] = 0; weight_mem[k] = 0;
            for (r = 0; r < 16; r = r + 1) begin
                av = ((k*k + 3*r*r + 5*k*r + 7) % 16) - 8;
                act_mem[k][r*4 +: 4] = av[3:0];
            end
            for (c = 0; c < 16; c = c + 1) begin
                wv = ((3*k*k + c*c + 7*k*c + 11) % 16) - 8;
                weight_mem[k][c*4 +: 4] = wv[3:0];
            end
        end
        repeat (3) @(posedge clk); rst_n <= 1;
        abort_midrun();
        run_case(7); run_case(0); run_case(13);
        $display("PASS: X3-Y5 reset-abort locked regression, K=7/0/13, 768 clean-restart outputs verified");
        $finish;
    end
    initial begin #300000; $display("FAIL timeout"); $fatal(1); end
endmodule
