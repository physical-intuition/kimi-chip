`timescale 1ns/1ps

// Sixteen-channel parallel depthwise convolution for alpha and beta gates.
// Four INT8 history taps and four INT4 weights are consumed per lane.
module conv_unit (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          in_valid,
    output wire          in_ready,
    input  wire [511:0]  history_data,
    input  wire [255:0]  alpha_weights,
    input  wire [255:0]  beta_weights,
    input  wire [255:0]  alpha_bias,
    input  wire [255:0]  beta_bias,
    output reg           out_valid,
    output reg  [127:0]  alpha_out,
    output reg  [127:0]  beta_out
);
    reg stage_valid;
    reg signed [15:0] alpha_sum [0:15];
    reg signed [15:0] beta_sum [0:15];
    integer lane, tap;
    reg signed [15:0] a_temp, b_temp;
    reg signed [7:0] x_temp;
    reg signed [3:0] aw_temp, bw_temp;

    assign in_ready = 1'b1;

    function [7:0] sigmoid_pwl;
        input signed [15:0] x;
        begin
            if (x <= -16'sd512) sigmoid_pwl = 8'd0;
            else if (x >= 16'sd512) sigmoid_pwl = 8'd127;
            else sigmoid_pwl = 8'd64 + (x >>> 3);
        end
    endfunction

    function signed [7:0] tanh_pwl;
        input signed [15:0] x;
        begin
            if (x <= -16'sd256) tanh_pwl = -8'sd127;
            else if (x >= 16'sd256) tanh_pwl = 8'sd127;
            else tanh_pwl = x >>> 1;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            stage_valid <= 1'b0;
            out_valid <= 1'b0;
            alpha_out <= 128'd0;
            beta_out <= 128'd0;
            for (lane = 0; lane < 16; lane = lane + 1) begin
                alpha_sum[lane] <= 16'sd0;
                beta_sum[lane] <= 16'sd0;
            end
        end else begin
            stage_valid <= in_valid && in_ready;
            out_valid <= stage_valid;
            if (in_valid && in_ready) begin
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    a_temp = $signed(alpha_bias[lane*16 +: 16]);
                    b_temp = $signed(beta_bias[lane*16 +: 16]);
                    for (tap = 0; tap < 4; tap = tap + 1) begin
                        x_temp = history_data[(lane*4+tap)*8 +: 8];
                        aw_temp = alpha_weights[(lane*4+tap)*4 +: 4];
                        bw_temp = beta_weights[(lane*4+tap)*4 +: 4];
                        a_temp = a_temp + x_temp * aw_temp;
                        b_temp = b_temp + x_temp * bw_temp;
                    end
                    alpha_sum[lane] <= a_temp;
                    beta_sum[lane] <= b_temp;
                end
            end
            if (stage_valid) begin
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    alpha_out[lane*8 +: 8] <= sigmoid_pwl(alpha_sum[lane]);
                    beta_out[lane*8 +: 8] <= tanh_pwl(beta_sum[lane]);
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk)
        if (rst_n && in_valid)
            assert (in_ready) else $error("conv input dropped");
`endif
endmodule
