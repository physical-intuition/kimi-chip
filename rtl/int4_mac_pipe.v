// Pipelined INT4 Multiply-Accumulate Unit
// 2-stage pipeline: multiply | accumulate
// Higher fmax at cost of 1 cycle latency
module int4_mac_pipe (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        clear,
    input  wire [3:0]  a,
    input  wire [3:0]  w,
    output reg  [19:0] acc
);

    // Pipeline stage 1: register inputs and compute product
    reg signed [7:0] prod_r;
    reg en_r, clear_r;
    
    wire signed [3:0] a_s = a;
    wire signed [3:0] w_s = w;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_r <= 8'b0;
            en_r <= 0;
            clear_r <= 0;
        end else begin
            prod_r <= a_s * w_s;
            en_r <= en;
            clear_r <= clear;
        end
    end
    
    // Pipeline stage 2: accumulate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 20'b0;
        else if (clear_r)
            acc <= 20'b0;
        else if (en_r)
            acc <= acc + {{12{prod_r[7]}}, prod_r};
    end

endmodule
