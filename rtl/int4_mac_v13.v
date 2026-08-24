// INT4 MAC v13 - v11's registered-product pipeline, TWO elements per cycle.
//
// Each en-cycle consumes an element PAIR: prod_q <= a0*b0 + a1*b1.
// stage P: the two 4x4 multiplies run in parallel, one 9-bit add combines
//          them (|a*b| <= 64 each, |pair sum| <= 128, 9-bit signed holds it)
// stage A: chunk <= chunk + prod_q (13-bit: 16 pair-adds x 128 = 2048 <= 4095)
// fold   : two-stage as v11 (stage register, then the 24-bit add), so no
//          single cycle contains more than one of {multiply, chunk add,
//          24b add}. Acc bound unchanged: K elements x 64 max per element,
//          65535 x 64 = 4194240 <= 2^23-1.
module int4_mac_v13 (
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_q <= 0; en_q <= 0; drain_q <= 0;
            chunk <= 0; stage <= 0; stage_v <= 0; acc <= 0;
        end else if (clear) begin
            prod_q <= 0; en_q <= 0; drain_q <= 0;
            chunk <= 0; stage <= 0; stage_v <= 0; acc <= 0;
        end else begin
            // stage P: capture the pair product-sum
            if (en) prod_q <= a0*b0 + a1*b1;
            en_q <= en;
            drain_q <= drain;
            // stage A / fold capture
            if (drain_q) begin
                stage <= chunk;
                stage_v <= 1'b1;
                chunk <= en_q ? {{4{prod_q[8]}}, prod_q} : 13'd0;
            end else begin
                if (en_q) chunk <= chunk + {{4{prod_q[8]}}, prod_q};
                stage_v <= 1'b0;
            end
            // fold complete: wide add on its own cycle
            if (stage_v) acc <= acc + {{11{stage[12]}}, stage};
        end
    end
endmodule
