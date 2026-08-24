`timescale 1ns/1ps

// X2-Y2 preserves X2-Y1's linted indexed-readout datapath. Its experimental
// change is a stronger physical capacitance-repair margin after Y1 retained
// one final extracted max-cap violation under CAP_MARGIN=20.
module x2_y2_kimi (
    input wire clk, input wire rst_n, input wire start, input wire [11:0] k_dim,
    output wire act_req, output wire [11:0] act_addr, input wire [63:0] act_rdata,
    output wire weight_req, output wire [11:0] weight_addr, input wire [63:0] weight_rdata,
    output wire out_we, output wire [13:0] out_addr, output wire [23:0] out_wdata,
    output wire busy, output wire done
);
    x1_y5_kimi core (
        .clk(clk), .rst_n(rst_n), .start(start), .k_dim(k_dim),
        .act_req(act_req), .act_addr(act_addr), .act_rdata(act_rdata),
        .weight_req(weight_req), .weight_addr(weight_addr), .weight_rdata(weight_rdata),
        .out_we(out_we), .out_addr(out_addr), .out_wdata(out_wdata),
        .busy(busy), .done(done)
    );
endmodule
