`timescale 1ns/1ps

// X1-Y2: 16x16 signed INT4 outer-product engine.
//
// Y1 serialized a flat 256-entry accumulator file by shifting all 6144 bits
// every drain cycle. That global shift network could not route. Y2 partitions
// the state into sixteen physical 16-entry row banks. Only the selected bank
// shifts during drain, and a 16:1 bank-head mux feeds the output port.
module x1_y2_kimi (
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
    reg [11:0] issued;
    reg [11:0] consumed;
    reg        read_valid;
    reg [3:0]  drain_row;
    reg [3:0]  drain_col;

    // Sixteen row-local banks. Each bank has only a 16-word drain shift path.
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
            drain_row   <= 4'd0;
            drain_col   <= 4'd0;
            out_we      <= 1'b0;
            out_addr    <= 14'd0;
            out_wdata   <= 24'd0;
            done        <= 1'b0;
            for (i = 0; i < 16; i = i + 1)
                for (j = 0; j < 16; j = j + 1)
                    accum_bank[i][j] <= 24'sd0;
        end else begin
            out_we <= 1'b0;
            done   <= 1'b0;

            case (state)
                S_IDLE: begin
                    read_valid <= 1'b0;
                    if (start) begin
                        issued     <= 12'd0;
                        consumed   <= 12'd0;
                        drain_row  <= 4'd0;
                        drain_col  <= 4'd0;
                        for (i = 0; i < 16; i = i + 1)
                            for (j = 0; j < 16; j = j + 1)
                                accum_bank[i][j] <= 24'sd0;
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
                        for (r = 0; r < 16; r = r + 1) begin
                            for (c = 0; c < 16; c = c + 1) begin
                                act_lane    = $signed(act_rdata[r*4 +: 4]);
                                weight_lane = $signed(weight_rdata[c*4 +: 4]);
                                product     = act_lane * weight_lane;
                                accum_bank[r][c] <= accum_bank[r][c] + product;
                            end
                        end
                        consumed <= consumed + 1'b1;
                        if (consumed + 1'b1 == k_dim) begin
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

                    // Explicit bank selection keeps the mux at 16:1. Within a
                    // selected bank the head is fixed, so there is no 256:1 mux.
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

                    // Shift only one 384-bit row bank, not the entire 6144-bit
                    // accumulator file. The case arms are intentionally static.
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
endmodule
