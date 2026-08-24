`timescale 1ns/1ps
// X9 contract: signed INT24 Q8 value to signed INT8, arithmetic shift by
// eight followed by saturation. This block is purely combinational.
module requant_24_to_8(
    input  wire signed [23:0] acc,
    output reg  signed [7:0]  out
);
    reg signed [23:0] shifted;
    always @* begin
        shifted = acc >>> 8;
        if (shifted > 24'sd127)
            out = 8'sd127;
        else if (shifted < -24'sd128)
            out = -8'sd128;
        else
            out = shifted[7:0];
    end
endmodule
