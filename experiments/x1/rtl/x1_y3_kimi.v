`timescale 1ns/1ps

// X1-Y3: timing-focused refinement of the routed Y2 banked design.
//
// Y2's worst global-route path was the external k_dim input to act_req, not the
// MAC datapath. Y3 latches k_dim at start so active-cycle request generation is
// entirely internal. The 16 row-local drain banks are retained because they
// proved routable. Accumulator storage is moved to a resetless always block;
// every operation clears it on start, so distributing asynchronous reset to
// 6144 datapath bits is unnecessary.
module x1_y3_kimi (
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

    // Control and externally visible outputs retain asynchronous reset.
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
                        k_dim_q    <= k_dim;
                        issued     <= 12'd0;
                        consumed   <= 12'd0;
                        drain_row  <= 4'd0;
                        drain_col  <= 4'd0;
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
                    out_we   <= 1'b1;
                    out_addr <= {6'd0, drain_row, drain_col};
                    case (drain_row)
                        4'd0:  out_wdata <= accum_bank[0][0];
                        4'd1:  out_wdata <= accum_bank[1][0];
                        4'd2:  out_wdata <= accum_bank[2][0];
                        4'd3:  out_wdata <= accum_bank[3][0];
                        4'd4:  out_wdata <= accum_bank[4][0];
                        4'd5:  out_wdata <= accum_bank[5][0];
                        4'd6:  out_wdata <= accum_bank[6][0];
                        4'd7:  out_wdata <= accum_bank[7][0];
                        4'd8:  out_wdata <= accum_bank[8][0];
                        4'd9:  out_wdata <= accum_bank[9][0];
                        4'd10: out_wdata <= accum_bank[10][0];
                        4'd11: out_wdata <= accum_bank[11][0];
                        4'd12: out_wdata <= accum_bank[12][0];
                        4'd13: out_wdata <= accum_bank[13][0];
                        4'd14: out_wdata <= accum_bank[14][0];
                        default: out_wdata <= accum_bank[15][0];
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

    // Datapath storage needs no asynchronous reset. S_IDLE/start clears all
    // words before either RUN or zero-K DRAIN can observe them.
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
        end else if (state == S_DRAIN) begin
            case (drain_row)
                4'd0:  for (i = 0; i < 15; i = i + 1) accum_bank[0][i]  <= accum_bank[0][i+1];
                4'd1:  for (i = 0; i < 15; i = i + 1) accum_bank[1][i]  <= accum_bank[1][i+1];
                4'd2:  for (i = 0; i < 15; i = i + 1) accum_bank[2][i]  <= accum_bank[2][i+1];
                4'd3:  for (i = 0; i < 15; i = i + 1) accum_bank[3][i]  <= accum_bank[3][i+1];
                4'd4:  for (i = 0; i < 15; i = i + 1) accum_bank[4][i]  <= accum_bank[4][i+1];
                4'd5:  for (i = 0; i < 15; i = i + 1) accum_bank[5][i]  <= accum_bank[5][i+1];
                4'd6:  for (i = 0; i < 15; i = i + 1) accum_bank[6][i]  <= accum_bank[6][i+1];
                4'd7:  for (i = 0; i < 15; i = i + 1) accum_bank[7][i]  <= accum_bank[7][i+1];
                4'd8:  for (i = 0; i < 15; i = i + 1) accum_bank[8][i]  <= accum_bank[8][i+1];
                4'd9:  for (i = 0; i < 15; i = i + 1) accum_bank[9][i]  <= accum_bank[9][i+1];
                4'd10: for (i = 0; i < 15; i = i + 1) accum_bank[10][i] <= accum_bank[10][i+1];
                4'd11: for (i = 0; i < 15; i = i + 1) accum_bank[11][i] <= accum_bank[11][i+1];
                4'd12: for (i = 0; i < 15; i = i + 1) accum_bank[12][i] <= accum_bank[12][i+1];
                4'd13: for (i = 0; i < 15; i = i + 1) accum_bank[13][i] <= accum_bank[13][i+1];
                4'd14: for (i = 0; i < 15; i = i + 1) accum_bank[14][i] <= accum_bank[14][i+1];
                default: for (i = 0; i < 15; i = i + 1) accum_bank[15][i] <= accum_bank[15][i+1];
            endcase
        end
    end
endmodule
