// int4_mac_v9f - v9 semantics, fast chunk path.
//
// v9's chunk update is adder -> drain mux -> register: the mux trails the
// adder on the critical (product) arrival. os16's measured worst path is
// exactly this (Wx -> mult -> add -> drain mux -> chunk). v9f moves both
// selects to the EARLY operands: the drain mux zeroes the chunk operand
// (register output, arrives early) and en gates the product operand one
// AND-level; the adder output lands in the register directly. Behavior
// is bit-identical to int4_mac_v9:
//   drain: acc += chunk;  chunk <= en ? prod : 0
//   en   : chunk <= chunk + prod
module int4_mac_v9f (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,
    input wire signed [3:0] a,
    input wire signed [3:0] b,
    output reg signed [23:0] acc
);
    reg signed [11:0] chunk;
    wire signed [7:0]  prod = a * b;
    wire signed [11:0] pin  = en    ? {{4{prod[7]}}, prod} : 12'sd0;
    wire signed [11:0] cin  = drain ? 12'sd0 : chunk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chunk <= 0; acc <= 0;
        end else if (clear) begin
            chunk <= 0; acc <= 0;
        end else begin
            if (en | drain) chunk <= cin + pin;
            if (drain) acc <= acc + {{12{chunk[11]}}, chunk};
        end
    end
endmodule
