`timescale 1ns/1ps

// X1-Y5: local indexed readout refinement of Y3/Y4.
//
// Each 16-word row bank keeps its physical locality during accumulation. Unlike
// Y2-Y4, DRAIN never shifts 15 accumulator registers per output. The selected
// row's 16 words feed a local 16:1 indexed read mux. This trades repeated
// register switching and row-shift wiring for a fixed local mux cone. It keeps
// one result write per cycle and the external SRAM/output contract unchanged.
module x1_y5_kimi (
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

    reg [1:0]  state;
    reg [11:0] k_dim_q;
    reg [11:0] issued;
    reg [11:0] consumed;
    reg        read_valid;
    reg [3:0]  drain_row;
    reg [3:0]  drain_col;

    reg signed [23:0] accum_bank [0:15][0:15];

    integer r;
    integer c;
    integer i;
    integer j;
    reg signed [3:0] act_lane;
    reg signed [3:0] weight_lane;
    reg signed [7:0] product;

    assign busy = (state != S_IDLE);

    // SRAM response is sampled one cycle after each request, matching Y3/Y4.
    always @* begin
        act_req     = 1'b0;
        act_addr    = issued;
        weight_req  = 1'b0;
        weight_addr = issued;
        if (state == S_RUN && issued < k_dim_q) begin
            act_req    = 1'b1;
            weight_req = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            k_dim_q     <= 12'd0;
            issued      <= 12'd0;
            consumed    <= 12'd0;
            read_valid  <= 1'b0;
            drain_row   <= 4'd0;
            drain_col   <= 4'd0;
            out_we      <= 1'b0;
            out_addr    <= 14'd0;
            out_wdata   <= 24'd0;
            done        <= 1'b0;
        end else begin
            out_we <= 1'b0;
            done   <= 1'b0;
            case (state)
                S_IDLE: begin
                    read_valid <= 1'b0;
                    if (start) begin
                        k_dim_q   <= k_dim;
                        issued    <= 12'd0;
                        consumed  <= 12'd0;
                        drain_row <= 4'd0;
                        drain_col <= 4'd0;
                        if (k_dim == 0)
                            state <= S_DRAIN;
                        else
                            state <= S_RUN;
                    end
                end
                S_RUN: begin
                    read_valid <= act_req && weight_req;
                    if (act_req && weight_req)
                        issued <= issued + 1'b1;
                    if (read_valid) begin
                        consumed <= consumed + 1'b1;
                        if (consumed + 1'b1 == k_dim_q) begin
                            state      <= S_DRAIN;
                            read_valid <= 1'b0;
                            drain_row  <= 4'd0;
                            drain_col  <= 4'd0;
                        end
                    end
                end
                S_DRAIN: begin
                    out_we    <= 1'b1;
                    out_addr  <= {6'd0, drain_row, drain_col};
                    // Indexed readout, no accumulator mutation in DRAIN.
                    case (drain_row)
                        4'd0:  out_wdata <= accum_bank[0][drain_col];
                        4'd1:  out_wdata <= accum_bank[1][drain_col];
                        4'd2:  out_wdata <= accum_bank[2][drain_col];
                        4'd3:  out_wdata <= accum_bank[3][drain_col];
                        4'd4:  out_wdata <= accum_bank[4][drain_col];
                        4'd5:  out_wdata <= accum_bank[5][drain_col];
                        4'd6:  out_wdata <= accum_bank[6][drain_col];
                        4'd7:  out_wdata <= accum_bank[7][drain_col];
                        4'd8:  out_wdata <= accum_bank[8][drain_col];
                        4'd9:  out_wdata <= accum_bank[9][drain_col];
                        4'd10: out_wdata <= accum_bank[10][drain_col];
                        4'd11: out_wdata <= accum_bank[11][drain_col];
                        4'd12: out_wdata <= accum_bank[12][drain_col];
                        4'd13: out_wdata <= accum_bank[13][drain_col];
                        4'd14: out_wdata <= accum_bank[14][drain_col];
                        default: out_wdata <= accum_bank[15][drain_col];
                    endcase
                    if (drain_col == 4'd15) begin
                        drain_col <= 4'd0;
                        if (drain_row == 4'd15) begin
                            state <= S_IDLE;
                            done  <= 1'b1;
                        end else begin
                            drain_row <= drain_row + 1'b1;
                        end
                    end else begin
                        drain_col <= drain_col + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // Storage is resetless. Every accepted operation initializes all cells
    // before a RUN response or K=0 DRAIN can read them.
    always @(posedge clk) begin
        if (state == S_IDLE && start) begin
            for (i = 0; i < 16; i = i + 1)
                for (j = 0; j < 16; j = j + 1)
                    accum_bank[i][j] <= 24'sd0;
        end else if (state == S_RUN && read_valid) begin
            for (r = 0; r < 16; r = r + 1) begin
                for (c = 0; c < 16; c = c + 1) begin
                    act_lane    = $signed(act_rdata[r*4 +: 4]);
                    weight_lane = $signed(weight_rdata[c*4 +: 4]);
                    product     = act_lane * weight_lane;
                    accum_bank[r][c] <= accum_bank[r][c] + product;
                end
            end
        end
    end
endmodule
