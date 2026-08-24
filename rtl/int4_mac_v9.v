// INT4 MAC v9 - hierarchical accumulator: overflow-proof for all expressible K.
//
// v4's single 12-bit accumulator caps K at 64 (and worst-case inputs can
// overflow it: 64 * 64 = 4096 > 2047). v9 keeps the same narrow, fast
// per-cycle path (8-bit product + 12-bit add) but drains into a wide 24-bit
// accumulator every CHUNK cycles. The 24-bit add happens once per chunk on a
// register-to-register path with no multiplier in front of it, so it is not
// the critical path. Chunk of 16: 16 adds x max|prod| 64 = 1024 <= 2047,
// provably safe in 12 bits signed. 24-bit wide accumulator: the binding
// K limit is the 16-bit k_dim (65535), and 65535*64 = 4194240 <= 8388607,
// so every expressible K is adversarially overflow-proof with 2x margin.
// Covers d_ff 22016 - and lets the core use the full 4096-deep SRAMs
// (v4's 6-bit addressing reached 1.6% of them).
module int4_mac_v9 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,   // pulse: fold the chunk accumulator into the wide one
    input wire signed [3:0] a,
    input wire signed [3:0] b,
    output reg signed [23:0] acc
);
    wire signed [7:0] prod = a * b;
    reg signed [11:0] chunk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chunk <= 0;
            acc   <= 0;
        end else if (clear) begin
            chunk <= 0;
            acc   <= 0;
        end else if (drain) begin
            acc   <= acc + {{12{chunk[11]}}, chunk};
            chunk <= en ? {{4{prod[7]}}, prod} : 12'd0;
        end else if (en) begin
            chunk <= chunk + {{4{prod[7]}}, prod};
        end
    end
endmodule
