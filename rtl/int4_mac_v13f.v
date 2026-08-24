// int4_mac_v13f - v13's registered pair-product MAC with v9f's fast
// chunk path. Two elements per en:
//   stage P: prod_q <= a0*b0 + a1*b1         (two mults + 9b add)
//   stage A: chunk <= cin + pin              (13b add, early-operand muxes:
//            drain_q zeroes the chunk operand, en_q gates the product)
//   fold   : two-stage as v13 (stage register, then the 24b add)
// Semantics identical to int4_mac_v13; en/drain interface identical to
// v9 (external drain = the cycle after the 16th en; internal _q delays
// align it with the registered product).
// Bounds: |pair sum| <= 128 (9b); 16 pair-adds x 128 = 2048 <= 4095 (13b).
module int4_mac_v13f (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,
    input wire signed [3:0] a0,
    input wire signed [3:0] a1,
    input wire signed [3:0] b0,
    input wire signed [3:0] b1,
    output reg signed [23:0] acc
);
    reg signed [8:0]  prod_q;
    reg en_q, drain_q;
    reg signed [12:0] chunk;
    reg signed [12:0] stage;
    reg stage_v;
    wire signed [12:0] pin = en_q    ? {{4{prod_q[8]}}, prod_q} : 13'sd0;
    wire signed [12:0] cin = drain_q ? 13'sd0 : chunk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_q <= 0; en_q <= 0; drain_q <= 0;
            chunk <= 0; stage <= 0; stage_v <= 0; acc <= 0;
        end else if (clear) begin
            prod_q <= 0; en_q <= 0; drain_q <= 0;
            chunk <= 0; stage <= 0; stage_v <= 0; acc <= 0;
        end else begin
            if (en) prod_q <= a0*b0 + a1*b1;
            en_q <= en;
            drain_q <= drain;
            if (en_q | drain_q) chunk <= cin + pin;
            if (drain_q) begin
                stage <= chunk; stage_v <= 1'b1;
            end else stage_v <= 1'b0;
            if (stage_v) acc <= acc + {{11{stage[12]}}, stage};
        end
    end
endmodule
