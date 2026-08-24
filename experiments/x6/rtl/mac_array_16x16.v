`timescale 1ns/1ps

// Y5 area fix: one 16-multiply lane is reused across the sixteen output lanes.
// A 128-bit activation beat is accepted, then the tile emits one complete
// sixteen-lane accumulation result after sixteen clocks.
module mac_array_16x16 (
    input wire clk,input wire rst_n,
    input wire weight_load_valid,output wire weight_load_ready,
    input wire weight_load_buffer,input wire [2:0] weight_load_beat,
    input wire [255:0] weight_load_data,
    input wire weight_activate,input wire weight_activate_buffer,
    input wire acc_clear,input wire mac_valid,output wire mac_ready,
    input wire [127:0] activation_data,
    output reg result_valid,output reg [383:0] result_data
);
    reg [255:0] weight0[0:3],weight1[0:3];
    reg buffer_full[0:1],active_buffer,busy;
    reg [3:0] lane;
    reg [127:0] activation_q;
    reg signed [23:0] accum[0:15];
    integer r,c,wi,wb;
    reg signed [15:0] sum_comb;
    reg signed [7:0] act_value;
    reg signed [3:0] weight_value;
    reg signed [24:0] accum_sum;

    function signed [23:0] sat24;
        input signed [24:0] value;
        begin
            if(value>25'sd8388607) sat24=24'sh7fffff;
            else if(value< -25'sd8388608) sat24=24'sh800000;
            else sat24=value[23:0];
        end
    endfunction

    assign weight_load_ready=!buffer_full[weight_load_buffer]||(weight_load_buffer!=active_buffer);
    assign mac_ready=buffer_full[active_buffer]&&!busy;

    always @(posedge clk) begin
        if(!rst_n) begin
            buffer_full[0]<=0; buffer_full[1]<=0; active_buffer<=0; busy<=0;
            lane<=0; activation_q<=0; result_valid<=0; result_data<=0;
            for(c=0;c<16;c=c+1) accum[c]<=0;
        end else begin
            result_valid<=0;
            if(weight_load_valid&&weight_load_ready) begin
                if(weight_load_buffer) weight1[weight_load_beat]<=weight_load_data;
                else weight0[weight_load_beat]<=weight_load_data;
                if(weight_load_beat==3) buffer_full[weight_load_buffer]<=1;
            end
            if(weight_activate&&buffer_full[weight_activate_buffer]) active_buffer<=weight_activate_buffer;
            if(acc_clear&&!busy) for(c=0;c<16;c=c+1) accum[c]<=0;
            if(mac_valid&&mac_ready) begin activation_q<=activation_data; lane<=0; busy<=1; end
            if(busy) begin
                sum_comb=0;
                for(r=0;r<16;r=r+1) begin
                    act_value=activation_q[r*8 +: 8];
                    wi=r*16+lane; wb=wi/64;
                    if(active_buffer) weight_value=weight1[wb][(wi%64)*4 +: 4];
                    else weight_value=weight0[wb][(wi%64)*4 +: 4];
                    sum_comb=sum_comb+act_value*weight_value;
                end
                accum_sum=$signed({accum[lane][23],accum[lane]})+$signed({{9{sum_comb[15]}},sum_comb});
                accum[lane]<=sat24(accum_sum);
                result_data[lane*24 +: 24]<=sat24(accum_sum);
                if(lane==15) begin busy<=0; result_valid<=1; end
                else lane<=lane+1'b1;
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if(rst_n&&mac_valid) assert(mac_ready) else $error("MAC input without ready");
        if(rst_n&&acc_clear) assert(!busy) else $error("MAC clear while busy");
    end
`endif
endmodule
