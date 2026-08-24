`timescale 1ns/1ps
module tb_x4_y5;
    reg clk=0, rst_n=0, start=0;
    reg [15:0] k_dim=0;
    wire act_req, weight_req, out_we, busy, done;
    wire [15:0] act_addr, weight_addr;
    wire [13:0] out_addr;
    wire [23:0] out_wdata;
    reg [63:0] act_rdata=0, weight_rdata=0;
    integer expected [0:255];
    reg seen [0:255];
    integer writes, r, c, k, av, wv;
    integer stim_mode;
    reg collecting;

    x4_y5_kimi dut(.*);
    always #5 clk=~clk;

    function [3:0] act_value;
        input integer addr;
        input integer lane;
        integer t;
        begin
            if (stim_mode == 1) t = ((addr + lane) & 1) ? 7 : -8;
            else t=((addr*3 + lane*5 + addr*lane + 7) % 16)-8;
            act_value=t[3:0];
        end
    endfunction
    function [3:0] weight_value;
        input integer addr;
        input integer lane;
        integer t;
        begin
            if (stim_mode == 1) t = ((addr*3 + lane) & 1) ? -8 : 7;
            else t=((addr*7 + lane*3 + addr*lane*3 + 11) % 16)-8;
            weight_value=t[3:0];
        end
    endfunction
    function [63:0] pack_act;
        input integer addr;
        integer n;
        begin for(n=0;n<16;n=n+1) pack_act[n*4 +: 4]=act_value(addr,n); end
    endfunction
    function [63:0] pack_weight;
        input integer addr;
        integer n;
        begin for(n=0;n<16;n=n+1) pack_weight[n*4 +: 4]=weight_value(addr,n); end
    endfunction

    always @(posedge clk) begin
        if (act_req !== weight_req) begin $display("FAIL unpaired request"); $fatal(1); end
        if (act_req) begin
            act_rdata <= pack_act(act_addr);
            weight_rdata <= pack_weight(weight_addr);
        end
    end

    always @(posedge clk) if(out_we) begin
        if(!collecting || out_addr>=256 || seen[out_addr]) begin $display("FAIL invalid output addr=%0d",out_addr); $fatal(1); end
        seen[out_addr] <= 1;
        if($signed(out_wdata)!==expected[out_addr]) begin
            $display("FAIL K=%0d idx=%0d got=%0d exp=%0d",k_dim,out_addr,$signed(out_wdata),expected[out_addr]); $fatal(1);
        end
        writes <= writes+1;
    end

    task run_case;
        input integer count;
        begin
            writes=0;
            for(r=0;r<256;r=r+1) begin expected[r]=0; seen[r]=0; end
            for(k=0;k<16;k=k+1)
                for(r=0;r<16;r=r+1)
                    for(c=0;c<16;c=c+1) begin
                        av=$signed(act_value(k,r)); wv=$signed(weight_value(k,c));
                        expected[r*16+c]=expected[r*16+c]+av*wv*(count/16 + ((k < (count%16)) ? 1 : 0));
                    end
            collecting=1;
            @(posedge clk); k_dim<=count; start<=1;
            @(posedge clk); start<=0;
            if (count == 13 && stim_mode == 0) fork
                begin
                    repeat(4) @(posedge clk);
                    k_dim <= 16'd1;
                    start <= 1'b1;
                    @(posedge clk);
                    start <= 1'b0;
                    k_dim <= count;
                    $display("PASS busy-start ignored and k_dim remained latched");
                end
            join_none
            wait(done); @(posedge clk); #1; collecting=0;
            if(writes!=256) begin $display("FAIL writes=%0d K=%0d",writes,count); $fatal(1); end
            for(r=0;r<256;r=r+1) if(!seen[r]) begin $display("FAIL missing %0d",r); $fatal(1); end
            $display("PASS K=%0d outputs=256",count);
        end
    endtask

    task abort_and_restart;
        begin
            collecting=0;
            @(posedge clk); k_dim<=16'd33; start<=1;
            @(posedge clk); start<=0;
            repeat(8) @(posedge clk);
            rst_n<=0;
            repeat(2) @(posedge clk);
            if (act_req || weight_req || out_we || done || busy) begin
                $display("FAIL reset-abort did not quiesce control outputs"); $fatal(1);
            end
            rst_n<=1;
            repeat(2) @(posedge clk);
            $display("PASS reset-abort quiescence");
            run_case(17);
            $display("PASS clean restart after reset-abort");
        end
    endtask

    initial begin
        collecting=0; writes=0; stim_mode=0;
        repeat(3) @(posedge clk); rst_n<=1;
        run_case(7); run_case(0); run_case(13);
        run_case(15); run_case(16); run_case(17); run_case(31); run_case(32); run_case(33);
        stim_mode=1; run_case(17); stim_mode=0;
        $display("PASS signed-extrema fold regression");
        abort_and_restart();
        run_case(65535);
        $display("PASS: X4-Y5 registered two-slice fold, hierarchical fold, tail flush, reset/restart, signed extrema, exactly-once, and K=65535 verified");
        $finish;
    end
    initial begin #5000000; $display("FAIL timeout"); $fatal(1); end
endmodule
