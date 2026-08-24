`timescale 1ns/1ps
module tb_x6_top;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, in_valid=0, in_last=0, out_ready=1;
    reg [127:0] activation_in=0, skip_in=0;
    wire in_ready,out_valid,out_last,busy,fault;
    wire [127:0] activation_out;
    wire [5:0] weight_bank_req;
    wire [95:0] weight_bank_addr;
    reg [5:0] weight_bank_valid;
    reg [1535:0] weight_bank_rdata;
    reg [255:0] conv_alpha_weights=0,conv_beta_weights=0;
    reg [255:0] conv_alpha_bias=0,conv_beta_bias={16{16'd128}};
    wire state_read_req,state_write_req,state_read_bank,state_write_bank;
    wire [6:0] state_read_addr,state_write_addr;
    reg state_row_valid=0;
    reg [3071:0] state_row_rdata=0;
    wire [3071:0] state_row_wdata;

    reg [3071:0] state0[0:127],state1[0:127];
    reg pending_read, pending_bank;
    reg [6:0] pending_addr;
    integer i,r,c,lane,word,addr,projection,tile_pair,chunk,beat;
    integer cycles=0,outputs=0,failures=0,mac_cycles=0,conv_cycles=0,state_cycles=0;
    reg [255:0] w0,w1;

    x6_top dut(.*);

    always @* begin
        weight_bank_valid=0;
        weight_bank_rdata=0;
        if(weight_bank_req[0] && weight_bank_req[1]) begin
            weight_bank_valid[1:0]=2'b11;
            addr=weight_bank_addr[15:0];
            projection=addr/128;
            tile_pair=(addr%128)/32;
            chunk=(addr%32)/4;
            beat=addr%4;
            w0=0; w1=0;
            for(word=0;word<64;word=word+1) begin
                r=(beat*64+word)/16;
                c=(beat*64+word)%16;
                if((chunk*16+r)==(tile_pair*16+c)) w0[word*4 +: 4]=4'd1;
                if((chunk*16+r)==((tile_pair+4)*16+c)) w1[word*4 +: 4]=4'd1;
            end
            weight_bank_rdata[255:0]=w0;
            weight_bank_rdata[511:256]=w1;
        end
    end

    always @(posedge clk) begin
        state_row_valid <= pending_read;
        if(pending_read) state_row_rdata <= pending_bank ? state1[pending_addr] : state0[pending_addr];
        pending_read <= state_read_req;
        pending_bank <= state_read_bank;
        pending_addr <= state_read_addr;
        if(state_write_req) begin
            if(state_write_bank) state1[state_write_addr] <= state_row_wdata;
            else state0[state_write_addr] <= state_row_wdata;
        end
        if(rst_n) cycles<=cycles+1;
        if(dut.phase==5'd4) mac_cycles<=mac_cycles+1;
        if(dut.conv_in_valid) conv_cycles<=conv_cycles+1;
        if(dut.state_input_valid) state_cycles<=state_cycles+1;
    end

    always @(negedge clk) if(rst_n && out_valid) begin
        if(activation_out !== {16{8'd4}}) begin
            $display("FAIL TOP output beat %0d got=%h expected=%h",outputs,activation_out,{16{8'd4}});
            failures=failures+1;
        end
        if(out_last !== (outputs==7)) begin
            $display("FAIL TOP last protocol beat=%0d last=%b",outputs,out_last);
            failures=failures+1;
        end
        outputs=outputs+1;
    end

    initial begin
        pending_read=0; pending_bank=0; pending_addr=0;
        for(i=0;i<128;i=i+1) begin state0[i]=0; state1[i]=0; end
        repeat(4) @(posedge clk); rst_n=1;
        for(i=0;i<8;i=i+1) begin
            @(negedge clk); in_valid=1; activation_in={16{8'd64}}; skip_in={16{8'd3}}; in_last=(i==7);
            if(!in_ready) begin $display("FAIL TOP input backpressure beat=%0d",i); failures=failures+1; end
        end
        @(negedge clk); in_valid=0; in_last=0;
        wait(outputs==8);
        @(negedge clk);
        if(mac_cycles != 128) begin $display("FAIL TOP MAC activity=%0d expected=128",mac_cycles); failures=failures+1; end
        if(conv_cycles != 8) begin $display("FAIL TOP conv activity=%0d expected=8",conv_cycles); failures=failures+1; end
        if(state_cycles != 256) begin $display("FAIL TOP state activity=%0d expected=256",state_cycles); failures=failures+1; end
        if(fault) begin $display("FAIL TOP fault asserted"); failures=failures+1; end
        if(failures==0) $display("PASS tb_x6_top: full K/V/Q->conv->state->O->norm->residual flow, cycles=%0d",cycles);
        else $display("FAIL tb_x6_top: %0d errors",failures);
        $finish_and_return(failures!=0);
    end

    initial begin
        repeat(100000) @(posedge clk);
        $display("FAIL TOP timeout phase=%0d outputs=%0d",dut.phase,outputs);
        $finish_and_return(1);
    end
endmodule
