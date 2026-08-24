`timescale 1ns/1ps

// Registered three-source/four-destination activation router.
// Selector 0=MAC0, 1=MAC1, 2=external; 3 disables a destination.
module activation_crossbar (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          route_valid,
    input  wire [255:0]  mac0_data,
    input  wire [255:0]  mac1_data,
    input  wire [255:0]  external_data,
    input  wire [1:0]    state_select,
    input  wire [1:0]    conv_select,
    input  wire [1:0]    norm_select,
    input  wire [1:0]    residual_select,
    output reg           state_valid,
    output reg           conv_valid,
    output reg           norm_valid,
    output reg           residual_valid,
    output reg  [255:0]  state_data,
    output reg  [255:0]  conv_data,
    output reg  [255:0]  norm_data,
    output reg  [255:0]  residual_data
);
    function [255:0] select_source;
        input [1:0] select;
        begin
            case (select)
                2'd0: select_source = mac0_data;
                2'd1: select_source = mac1_data;
                2'd2: select_source = external_data;
                default: select_source = 256'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_valid <= 1'b0;
            conv_valid <= 1'b0;
            norm_valid <= 1'b0;
            residual_valid <= 1'b0;
            state_data <= 256'd0;
            conv_data <= 256'd0;
            norm_data <= 256'd0;
            residual_data <= 256'd0;
        end else begin
            state_valid <= route_valid && state_select != 2'd3;
            conv_valid <= route_valid && conv_select != 2'd3;
            norm_valid <= route_valid && norm_select != 2'd3;
            residual_valid <= route_valid && residual_select != 2'd3;
            if (route_valid) begin
                state_data <= select_source(state_select);
                conv_data <= select_source(conv_select);
                norm_data <= select_source(norm_select);
                residual_data <= select_source(residual_select);
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) if (rst_n && route_valid) begin
        assert (!(state_select == 2'd3 && conv_select == 2'd3 &&
                  norm_select == 2'd3 && residual_select == 2'd3))
            else $error("activation route has no enabled destination");
    end
`endif
endmodule
