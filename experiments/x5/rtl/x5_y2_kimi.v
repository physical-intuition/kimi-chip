// X5-Y2: pipeline the 4x4 multiply and overlap requests, responses, and MAC commits.
// Target remains X5-Y1's 937.092 MHz so this iteration tests the observed
// act_rdata -> multiply -> chunk_accum setup failure without moving the goalpost.
module x5_y2_kimi (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [15:0]  k_dim,
    output reg          act_req,
    output reg  [15:0]  act_addr,
    input  wire [63:0]  act_rdata,
    output reg          weight_req,
    output reg  [15:0]  weight_addr,
    input  wire [63:0]  weight_rdata,
    output reg          out_we,
    output reg  [13:0]  out_addr,
    output reg  [23:0]  out_wdata,
    output wire         busy,
    output reg          done
);
    localparam S_IDLE        = 4'd0;
    localparam S_RUN         = 4'd1;
    localparam S_FOLD_LO0    = 4'd2;
    localparam S_FOLD_LO1    = 4'd3;
    localparam S_FOLD_HI     = 4'd4;
    localparam S_DRAIN_LOAD  = 4'd5;
    localparam S_DRAIN_WRITE = 4'd6;

    reg [3:0] state;
    reg [15:0] k_dim_q;
    reg [15:0] issued;
    reg [15:0] consumed;
    reg [4:0] chunk_issued;
    reg [4:0] chunk_count;
    reg response_valid;
    reg product_valid;
    reg fold_finishes_run;
    reg [3:0] drain_row, drain_col;

    reg signed [7:0] product_pipe [0:15][0:15];
    reg signed [11:0] chunk_accum [0:15][0:15];
    reg signed [23:0] wide_accum  [0:15][0:15];
    reg fold_carry6 [0:15][0:15];
    reg fold_carry12 [0:15][0:15];
    reg signed [23:0] drain_row_data [0:15];

    wire request_fire = (state == S_RUN) && (issued < k_dim_q) && (chunk_issued < 5'd16);
    wire commit_fire = (state == S_RUN) && product_valid;
    genvar gr, gc;

    assign busy = (state != S_IDLE);

    always @* begin
        act_req = request_fire;
        weight_req = request_fire;
        act_addr = issued;
        weight_addr = issued;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            k_dim_q <= 16'd0;
            issued <= 16'd0;
            consumed <= 16'd0;
            chunk_issued <= 5'd0;
            chunk_count <= 5'd0;
            response_valid <= 1'b0;
            product_valid <= 1'b0;
            fold_finishes_run <= 1'b0;
            drain_row <= 4'd0;
            drain_col <= 4'd0;
            out_we <= 1'b0;
            out_addr <= 14'd0;
            out_wdata <= 24'd0;
            done <= 1'b0;
        end else begin
            out_we <= 1'b0;
            done <= 1'b0;
            response_valid <= request_fire;
            product_valid <= response_valid;

            case (state)
                S_IDLE: begin
                    response_valid <= 1'b0;
                    product_valid <= 1'b0;
                    if (start) begin
                        k_dim_q <= k_dim;
                        issued <= 16'd0;
                        consumed <= 16'd0;
                        chunk_issued <= 5'd0;
                        chunk_count <= 5'd0;
                        fold_finishes_run <= 1'b0;
                        drain_row <= 4'd0;
                        drain_col <= 4'd0;
                        state <= (k_dim == 0) ? S_DRAIN_LOAD : S_RUN;
                    end
                end
                S_RUN: begin
                    if (request_fire) begin
                        issued <= issued + 1'b1;
                        chunk_issued <= chunk_issued + 1'b1;
                    end
                    if (commit_fire) begin
                        consumed <= consumed + 1'b1;
                        if ((chunk_count == 5'd15) || (consumed + 1'b1 == k_dim_q)) begin
                            fold_finishes_run <= (consumed + 1'b1 == k_dim_q);
                            chunk_count <= 5'd0;
                            response_valid <= 1'b0;
                            product_valid <= 1'b0;
                            state <= S_FOLD_LO0;
                        end else begin
                            chunk_count <= chunk_count + 1'b1;
                        end
                    end
                end
                S_FOLD_LO0: state <= S_FOLD_LO1;
                S_FOLD_LO1: state <= S_FOLD_HI;
                S_FOLD_HI: begin
                    if (fold_finishes_run) begin
                        drain_row <= 4'd0;
                        drain_col <= 4'd0;
                        state <= S_DRAIN_LOAD;
                    end else begin
                        chunk_issued <= 5'd0;
                        state <= S_RUN;
                    end
                end
                S_DRAIN_LOAD: begin
                    drain_col <= 4'd0;
                    state <= S_DRAIN_WRITE;
                end
                S_DRAIN_WRITE: begin
                    out_we <= 1'b1;
                    out_addr <= {6'd0, drain_row, drain_col};
                    out_wdata <= drain_row_data[drain_col];
                    if (drain_col == 4'd15) begin
                        drain_col <= 4'd0;
                        if (drain_row == 4'd15) begin
                            state <= S_IDLE;
                            done <= 1'b1;
                        end else begin
                            drain_row <= drain_row + 1'b1;
                            state <= S_DRAIN_LOAD;
                        end
                    end else begin
                        drain_col <= drain_col + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    generate
        for (gr = 0; gr < 16; gr = gr + 1) begin : g_row
            for (gc = 0; gc < 16; gc = gc + 1) begin : g_col
                wire signed [3:0] a_lane = act_rdata[gr*4 +: 4];
                wire signed [3:0] w_lane = weight_rdata[gc*4 +: 4];
                wire signed [7:0] product_comb = a_lane * w_lane;
                always @(posedge clk) begin
                    if (state == S_IDLE && start) begin
                        product_pipe[gr][gc] <= 8'sd0;
                        chunk_accum[gr][gc] <= 12'sd0;
                        wide_accum[gr][gc] <= 24'sd0;
                        fold_carry6[gr][gc] <= 1'b0;
                        fold_carry12[gr][gc] <= 1'b0;
                    end else begin
                        if (state == S_RUN && response_valid)
                            product_pipe[gr][gc] <= product_comb;
                        if (commit_fire)
                            chunk_accum[gr][gc] <= chunk_accum[gr][gc] + {{4{product_pipe[gr][gc][7]}}, product_pipe[gr][gc]};
                        else if (state == S_FOLD_LO0)
                            {fold_carry6[gr][gc], wide_accum[gr][gc][5:0]} <=
                                {1'b0, wide_accum[gr][gc][5:0]} + {1'b0, chunk_accum[gr][gc][5:0]};
                        else if (state == S_FOLD_LO1)
                            {fold_carry12[gr][gc], wide_accum[gr][gc][11:6]} <=
                                {1'b0, wide_accum[gr][gc][11:6]} + {1'b0, chunk_accum[gr][gc][11:6]} +
                                {{6{1'b0}}, fold_carry6[gr][gc]};
                        else if (state == S_FOLD_HI) begin
                            wide_accum[gr][gc][23:12] <= wide_accum[gr][gc][23:12] +
                                {12{chunk_accum[gr][gc][11]}} + {{11{1'b0}}, fold_carry12[gr][gc]};
                            chunk_accum[gr][gc] <= 12'sd0;
                        end
                    end
                end
            end
        end
        for (gc = 0; gc < 16; gc = gc + 1) begin : g_drain_stage
            always @(posedge clk) begin
                if (state == S_DRAIN_LOAD) begin
                    case (drain_row)
                        4'd0: drain_row_data[gc] <= wide_accum[0][gc];
                        4'd1: drain_row_data[gc] <= wide_accum[1][gc];
                        4'd2: drain_row_data[gc] <= wide_accum[2][gc];
                        4'd3: drain_row_data[gc] <= wide_accum[3][gc];
                        4'd4: drain_row_data[gc] <= wide_accum[4][gc];
                        4'd5: drain_row_data[gc] <= wide_accum[5][gc];
                        4'd6: drain_row_data[gc] <= wide_accum[6][gc];
                        4'd7: drain_row_data[gc] <= wide_accum[7][gc];
                        4'd8: drain_row_data[gc] <= wide_accum[8][gc];
                        4'd9: drain_row_data[gc] <= wide_accum[9][gc];
                        4'd10: drain_row_data[gc] <= wide_accum[10][gc];
                        4'd11: drain_row_data[gc] <= wide_accum[11][gc];
                        4'd12: drain_row_data[gc] <= wide_accum[12][gc];
                        4'd13: drain_row_data[gc] <= wide_accum[13][gc];
                        4'd14: drain_row_data[gc] <= wide_accum[14][gc];
                        default: drain_row_data[gc] <= wide_accum[15][gc];
                    endcase
                end
            end
        end
    endgenerate
endmodule
