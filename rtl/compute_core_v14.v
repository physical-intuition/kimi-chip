// compute_core v14 - v13's paired streaming + ACCUMULATE-PASS start.
//
// start with accum=0: classic pass (accumulators cleared first).
// start with accum=1: accumulators are PRESERVED and the new pass's
// products add on top -- the core-side half of ping-pong tiling: compute
// tile A, then accum-pass tile B that the host loaded meanwhile, etc.
// Chunk state needs no care across passes: the FLUSH chain always leaves
// chunk/stage empty, and addcnt/mac_drain are re-zeroed every CLEAR, so
// the 16-pair-add chunk bound holds within every pass regardless of how
// the previous one ended. Total accumulated elements across passes must
// stay <= 131,071 (64 * 131071 <= 2^23-1); per pass k_dim is bounded by
// the tile (2048 elements in fullchip_v14).
//
// Everything else is compute_core_v13 verbatim (lane registers, half-pair
// gating for odd k_dim, v11 FLUSH chain).
module compute_core_v14 #(
    parameter RD_LAT = 3
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire accum,               // sampled with start: 1 = keep accumulators
    input wire [15:0] k_dim,        // in ELEMENTS (per pass)
    output reg wgt_cs,
    output reg [15:0] wgt_addr,     // PAIR index (tile-local)
    input wire [63:0] wgt_rdata0,
    input wire [63:0] wgt_rdata1,
    output reg act_cs,
    output reg [15:0] act_addr,
    input wire [63:0] act_rdata0,
    input wire [63:0] act_rdata1,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam LAT = RD_LAT + 1;
    localparam CHUNK = 16;
    localparam IDLE=0, CLEAR=1, RUN=2, FLUSH=3, FLUSH2=4, FLUSH3=5, FLUSH4=6, DONE=7;
    reg [2:0] state;
    reg [15:0] p_iss, pairs;
    reg half_k;
    reg [LAT-1:0] vpipe;
    reg [LAT-1:0] hpipe;
    reg [3:0] addcnt;
    reg mac_clear, mac_drain;

    wire issuing    = (state == RUN) && (p_iss != pairs);
    wire half_issue = issuing && half_k && (p_iss == pairs - 16'd1);
    wire mac_en     = vpipe[LAT-1];
    wire hkill      = hpipe[LAT-2];

    wire [63:0] w0_bus, w1_bus, a0_bus, a1_bus;
    genvar g;
    generate for (g = 0; g < 16; g = g + 1) begin : laneq
        reg [3:0] wq0, wq1, aq0, aq1;
        always @(posedge clk) begin
            wq0 <= wgt_rdata0[g*4 +: 4];
            wq1 <= wgt_rdata1[g*4 +: 4];
            aq0 <= act_rdata0[g*4 +: 4];
            aq1 <= hkill ? 4'd0 : act_rdata1[g*4 +: 4];
        end
        assign w0_bus[g*4 +: 4] = wq0;
        assign w1_bus[g*4 +: 4] = wq1;
        assign a0_bus[g*4 +: 4] = aq0;
        assign a1_bus[g*4 +: 4] = aq1;
    end endgenerate

    mac_array_v13 #(.ROWS(16), .COLS(16)) array (
        .clk(clk), .rst_n(rst_n),
        .en(mac_en), .clear(mac_clear), .drain(mac_drain),
        .activations0(a0_bus), .activations1(a1_bus),
        .weights0(w0_bus), .weights1(w1_bus), .acc_out(acc_out));

    // addcnt/mac_drain re-zero on every pass entry (state==CLEAR), not just
    // on accumulator clears -- an accum pass must still fold on the same
    // 16-pair cadence from zero.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addcnt <= 0; mac_drain <= 0;
        end else if (mac_clear || state == CLEAR) begin
            addcnt <= 0; mac_drain <= 0;
        end else begin
            mac_drain <= (mac_en && addcnt == CHUNK-1) || (state == FLUSH);
            if (mac_en) addcnt <= (addcnt == CHUNK-1) ? 4'd0 : addcnt + 4'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; p_iss <= 0; pairs <= 0; half_k <= 0;
            vpipe <= 0; hpipe <= 0; done <= 0;
            mac_clear <= 0; wgt_cs <= 0; act_cs <= 0;
            wgt_addr <= 0; act_addr <= 0;
        end else begin
            vpipe <= {vpipe[LAT-2:0], issuing};
            hpipe <= {hpipe[LAT-2:0], half_issue};
            case (state)
                IDLE: if (start) begin
                    state <= CLEAR; mac_clear <= ~accum; done <= 0;
                end
                CLEAR: begin
                    mac_clear <= 0; p_iss <= 0; state <= RUN;
                    pairs <= (k_dim + 16'd1) >> 1;
                    half_k <= k_dim[0];
                    wgt_cs <= 1; act_cs <= 1;
                end
                RUN: begin
                    if (issuing) begin
                        wgt_addr <= p_iss; act_addr <= p_iss;
                        p_iss <= p_iss + 16'd1;
                    end
                    if (!issuing && vpipe == {LAT{1'b0}}) state <= FLUSH;
                end
                FLUSH: state <= FLUSH2;
                FLUSH2: state <= FLUSH3;
                FLUSH3: state <= FLUSH4;
                FLUSH4: state <= DONE;
                DONE: begin
                    done <= 1; wgt_cs <= 0; act_cs <= 0;
                    if (start) begin
                        state <= CLEAR; mac_clear <= ~accum; done <= 0;
                    end
                end
            endcase
        end
    end
endmodule
