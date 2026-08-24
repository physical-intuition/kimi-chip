// INT4 MAC v11 - fully pipelined: registered product + two-stage fold.
//
// Routed evidence from v10a: the binding path was data -> multiply -> 12b add
// -> chunk register, all in one cycle. v11 splits it:
//   stage P: prod_q <= a*b                (en)
//   stage A: chunk <= chunk + prod_q      (en_q, internal 1-cycle delay)
// And the fold (v10b's proven limiter) becomes two stages:
//   drain_q: stage <= chunk; chunk restarts
//   next:    acc <= acc + sext(stage)
// No single-cycle path contains more than one of {multiply, 12b add, 24b add}.
// Control-visible latency grows by 1 (en to add); folds complete 2 cycles
// after the external drain pulse. Drains are >=16 apart, so stages never
// collide. Chunk bound unchanged: 16 adds x 64 = 1024 <= 2047.
module int4_mac_v11 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,
    input wire signed [3:0] a,
    input wire signed [3:0] b,
    output reg signed [23:0] acc
);
    reg signed [7:0] prod_q;
    reg en_q, drain_q;
    reg signed [11:0] chunk;
    reg signed [11:0] stage;
    reg stage_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_q <= 0; en_q <= 0; drain_q <= 0;
            chunk <= 0; stage <= 0; stage_v <= 0; acc <= 0;
        end else if (clear) begin
            prod_q <= 0; en_q <= 0; drain_q <= 0;
            chunk <= 0; stage <= 0; stage_v <= 0; acc <= 0;
        end else begin
            // stage P: capture product
            if (en) prod_q <= a * b;
            en_q <= en;
            drain_q <= drain;
            // stage A / fold capture
            if (drain_q) begin
                stage <= chunk;
                stage_v <= 1'b1;
                chunk <= en_q ? {{4{prod_q[7]}}, prod_q} : 12'd0;
            end else begin
                if (en_q) chunk <= chunk + {{4{prod_q[7]}}, prod_q};
                stage_v <= 1'b0;
            end
            // fold complete: wide add on its own cycle
            if (stage_v) acc <= acc + {{12{stage[11]}}, stage};
        end
    end
endmodule
