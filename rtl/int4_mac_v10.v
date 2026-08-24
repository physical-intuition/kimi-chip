// INT4 MAC v10 - carry-save chunk accumulator + hierarchical fold.
//
// Same chunk/fold scheme as v9, but the per-cycle path drops the 12-bit
// ripple-carry add: the chunk lives as a redundant sum/carry pair and each
// cycle passes through one 3:2 compressor level (XOR + majority), so the
// fast path is mult -> one full-adder stage -> register.
//
// The redundancy is resolved ONLY at the fold: acc <= acc + sext((s+c) mod
// 2^12), registered, once per CHUNK adds. Unlike the earlier csa attempt
// (which resolved sum+carry combinationally on the output every cycle,
// putting a CPA back into the critical cone), outputs here are always
// registered.
//
// Bound: 16 adds x |prod|<=64 = 1024 <= 2047, so the true chunk value fits
// 12 bits signed and modular carry-save arithmetic is exact.
module int4_mac_v10 (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire clear,
    input wire drain,
    input wire signed [3:0] a,
    input wire signed [3:0] b,
    output reg signed [23:0] acc
);
    wire signed [7:0] prod = a * b;
    wire [11:0] pse = {{4{prod[7]}}, prod};

    reg [11:0] s, c;
    wire [11:0] new_s = s ^ c ^ pse;
    wire [11:0] new_c = ((s & c) | (s & pse) | (c & pse)) << 1;
    wire [11:0] resolved = s + c;   // evaluated only into the drain branch

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s <= 0; c <= 0; acc <= 0;
        end else if (clear) begin
            s <= 0; c <= 0; acc <= 0;
        end else if (drain) begin
            acc <= acc + {{12{resolved[11]}}, resolved};
            s   <= en ? pse : 12'd0;
            c   <= 12'd0;
        end else if (en) begin
            s <= new_s;
            c <= new_c;
        end
    end
endmodule
