`timescale 1ns/1ps

// X1-Y1 fresh baseline: a 16x16 outer-product INT4 MAC array with
// external synchronous SRAM interfaces. Each accepted SRAM word contains
// sixteen packed signed INT4 operands. One K step updates all 256 outputs.
module x1_y1_kimi (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [11:0]  k_dim,

    output reg          act_req,
    output reg  [11:0]  act_addr,
    input  wire [63:0]  act_rdata,
    output reg          weight_req,
    output reg  [11:0]  weight_addr,
    input  wire [63:0]  weight_rdata,

    output reg          out_we,
    output reg  [13:0]  out_addr,
    output reg  [23:0]  out_wdata,

    output wire         busy,
    output reg          done
);
    localparam S_IDLE  = 2'd0;
    localparam S_RUN   = 2'd1;
    localparam S_DRAIN = 2'd2;

    reg [1:0] state;
    reg [11:0] issued;
    reg [11:0] consumed;
    reg        read_valid;
    reg [7:0]  drain_index;

    // 24 bits safely cover 4096 signed INT4 products:
    // 4096 * max(|(-8)*(-8)|) = 262144.
    reg signed [23:0] accum [0:255];

    integer r;
    integer c;
    integer i;
    reg signed [3:0] act_lane;
    reg signed [3:0] weight_lane;
    reg signed [7:0] product;

    assign busy = (state != S_IDLE);

    always @* begin
        act_req     = 1'b0;
        act_addr    = issued;
        weight_req  = 1'b0;
        weight_addr = issued;
        if (state == S_RUN && issued < k_dim) begin
            act_req    = 1'b1;
            weight_req = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            issued      <= 12'd0;
            consumed    <= 12'd0;
            read_valid  <= 1'b0;
            drain_index <= 8'd0;
            out_we      <= 1'b0;
            out_addr    <= 14'd0;
            out_wdata   <= 24'd0;
            done        <= 1'b0;
            for (i = 0; i < 256; i = i + 1)
                accum[i] <= 24'sd0;
        end else begin
            out_we <= 1'b0;
            done   <= 1'b0;

            case (state)
                S_IDLE: begin
                    read_valid <= 1'b0;
                    if (start) begin
                        issued      <= 12'd0;
                        consumed    <= 12'd0;
                        drain_index <= 8'd0;
                        for (i = 0; i < 256; i = i + 1)
                            accum[i] <= 24'sd0;
                        if (k_dim == 0)
                            state <= S_DRAIN;
                        else
                            state <= S_RUN;
                    end
                end

                S_RUN: begin
                    // The SRAM contract is one-cycle synchronous read latency.
                    read_valid <= act_req && weight_req;
                    if (act_req && weight_req)
                        issued <= issued + 1'b1;

                    if (read_valid) begin
                        for (r = 0; r < 16; r = r + 1) begin
                            for (c = 0; c < 16; c = c + 1) begin
                                act_lane    = $signed(act_rdata[r*4 +: 4]);
                                weight_lane = $signed(weight_rdata[c*4 +: 4]);
                                product     = act_lane * weight_lane;
                                accum[r*16+c] <= accum[r*16+c] + product;
                            end
                        end
                        consumed <= consumed + 1'b1;
                        if (consumed + 1'b1 == k_dim) begin
                            state       <= S_DRAIN;
                            read_valid  <= 1'b0;
                            drain_index <= 8'd0;
                        end
                    end
                end

                S_DRAIN: begin
                    // Shift rather than dynamically indexing 256 registers.
                    // This avoids a 256:1 result mux on the output timing path.
                    out_we    <= 1'b1;
                    out_addr  <= {6'd0, drain_index};
                    out_wdata <= accum[0];
                    for (i = 0; i < 255; i = i + 1)
                        accum[i] <= accum[i+1];
                    if (drain_index == 8'hff) begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end else begin
                        drain_index <= drain_index + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
