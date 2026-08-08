// systolic_os16p - output-stationary systolic array, PAIRED (M3 stage 1):
// each PE consumes an element pair per cycle -> 512 MACs/cycle sustained,
// double os16 at (ideally) the same clock, because the PE is the
// registered-product int4_mac_v13f: the multiply cycle and the 13-bit
// chunk add are separate stages, both short, both local.
//
// Identical dataflow to systolic_os16 with k replaced by PAIR index p:
// the memory wrapper reads pair p and returns BOTH group words (elements
// 2p and 2p+1) each cycle -- the same two words/cycle the memories
// always supplied, now both consumed. Odd K and pad pairs fall out of
// element-level zeroing of activation words (a=0 kills the product
// regardless of the stale weight). Fold tag every 16 pairs (32
// elements); chunk bound 16 x 128 = 2048 <= 4095 (13b, in the MAC).
// Injection gated on STREAM (the diagonal phantom-wave lesson from
// os16 applies verbatim).
module systolic_os16p (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire accum,
    input wire [15:0] k_dim,        // ELEMENTS this pass
    output reg  wgt_cs,
    output reg  [15:0] wgt_addr,    // PAIR index
    input wire [63:0] wgt_word0,    // element 2p   (valid 3 cycles after addr)
    input wire [63:0] wgt_word1,    // element 2p+1
    output reg  act_cs,
    output reg  [15:0] act_addr,
    input wire [63:0] act_word0,
    input wire [63:0] act_word1,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam IDLE=0, INIT=1, STREAM=2, DONE=3;
    reg [1:0]  state;
    reg [15:0] k_lat;
    reg [15:0] p_pad;               // pairs, padded to a multiple of 16
    reg [15:0] sc;
    reg        aclr;

    wire issuing = (state == STREAM) && (sc < p_pad);
    reg  [2:0] iv;
    reg  [3:0] kmod_p1, kmod_p2, kmod_p3;
    reg        az0_p1, az0_p2, az0_p3;   // zero element 2p
    reg        az1_p1, az1_p2, az1_p3;   // zero element 2p+1

    // ---- transpose buffers, one per element slot ----
    reg [63:0] abuf0 [0:15];
    reg [63:0] abuf1 [0:15];
    reg [63:0] wbuf0 [0:15];
    reg [63:0] wbuf1 [0:15];
    always @(posedge clk) begin
        if (iv[2]) begin
            abuf0[kmod_p3] <= az0_p3 ? 64'd0 : act_word0;
            abuf1[kmod_p3] <= az1_p3 ? 64'd0 : act_word1;
            wbuf0[kmod_p3] <= wgt_word0;
            wbuf1[kmod_p3] <= wgt_word1;
        end
    end

    // ---- edge control (identical to os16, counting pairs) ----
    reg  [15:0] eact;
    reg  [3:0]  phase [0:15];
    reg  [15:0] wcnt  [0:15];
    reg  [15:0] ego;
    wire go0 = (state == STREAM) && (sc == 16'd3);
    integer x;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eact <= 0; ego <= 0;
        end else begin
            if (state == INIT) begin eact <= 0; ego <= 0; end
            else begin
                ego <= {ego[14:0], go0};
                for (x = 0; x < 16; x = x + 1) begin
                    if ((x == 0) ? go0 : ego[x-1]) begin
                        eact[x] <= 1'b1; phase[x] <= 0; wcnt[x] <= 0;
                    end else if (eact[x]) begin
                        phase[x] <= phase[x] + 4'd1;
                        wcnt[x]  <= wcnt[x] + 16'd1;
                    end
                end
            end
        end
    end

    // ---- operand/valid/tag pipes (pair-wide) ----
    reg signed [3:0] Ax0 [0:15][0:15];
    reg signed [3:0] Ax1 [0:15][0:15];
    reg signed [3:0] Wx0 [0:15][0:15];
    reg signed [3:0] Wx1 [0:15][0:15];
    reg              Vx  [0:15][0:15];
    reg              Fx  [0:15][0:15];
    wire inj = (state == STREAM);
    integer i, j;
    always @(posedge clk) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                Ax0[i][j] <= (j == 0)
                    ? ((inj && eact[i] && (wcnt[i] < p_pad))
                        ? $signed(abuf0[phase[i]][i*4 +: 4]) : 4'sd0)
                    : Ax0[i][j-1];
                Ax1[i][j] <= (j == 0)
                    ? ((inj && eact[i] && (wcnt[i] < p_pad))
                        ? $signed(abuf1[phase[i]][i*4 +: 4]) : 4'sd0)
                    : Ax1[i][j-1];
                Wx0[i][j] <= (i == 0)
                    ? ((inj && eact[j] && (wcnt[j] < p_pad))
                        ? $signed(wbuf0[phase[j]][j*4 +: 4]) : 4'sd0)
                    : Wx0[i-1][j];
                Wx1[i][j] <= (i == 0)
                    ? ((inj && eact[j] && (wcnt[j] < p_pad))
                        ? $signed(wbuf1[phase[j]][j*4 +: 4]) : 4'sd0)
                    : Wx1[i-1][j];
                Vx[i][j] <= (j == 0)
                    ? (inj && eact[i] && (wcnt[i] < p_pad))
                    : Vx[i][j-1];
                Fx[i][j] <= (j == 0)
                    ? (inj && eact[i] && (wcnt[i] < p_pad) && (phase[i] == 4'd15))
                    : Fx[i][j-1];
            end
        end
    end

    generate genvar gr, gc;
        for (gr = 0; gr < 16; gr = gr + 1) begin : row
            for (gc = 0; gc < 16; gc = gc + 1) begin : col
                reg fq;
                always @(posedge clk) fq <= Fx[gr][gc];
                int4_mac_v13f mac (
                    .clk(clk), .rst_n(rst_n),
                    .en(Vx[gr][gc]), .clear(aclr), .drain(fq),
                    .a0(Ax0[gr][gc]), .a1(Ax1[gr][gc]),
                    .b0(Wx0[gr][gc]), .b1(Wx1[gr][gc]),
                    .acc(acc_out[(gr*16 + gc)*24 +: 24]));
            end
        end
    endgenerate

    // ---- FSM ----
    wire [15:0] pairs = (k_dim + 16'd1) >> 1;
    wire [15:0] ppad  = (pairs + 16'd15) & 16'hFFF0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; done <= 0; aclr <= 0; sc <= 0;
            k_lat <= 0; p_pad <= 0;
            wgt_cs <= 0; act_cs <= 0; wgt_addr <= 0; act_addr <= 0;
            iv <= 0; kmod_p1 <= 0; kmod_p2 <= 0; kmod_p3 <= 0;
            az0_p1 <= 0; az0_p2 <= 0; az0_p3 <= 0;
            az1_p1 <= 0; az1_p2 <= 0; az1_p3 <= 0;
        end else begin
            aclr <= 0;
            iv <= {iv[1:0], issuing};
            kmod_p1 <= sc[3:0];  kmod_p2 <= kmod_p1;  kmod_p3 <= kmod_p2;
            // pair sc covers elements 2*sc and 2*sc+1; zero each act word
            // independently once its element index reaches K (17b compare)
            az0_p1 <= ({sc, 1'b0} >= {1'b0, k_lat});
            az0_p2 <= az0_p1; az0_p3 <= az0_p2;
            az1_p1 <= ({sc, 1'b1} >= {1'b0, k_lat});
            az1_p2 <= az1_p1; az1_p3 <= az1_p2;
            case (state)
                IDLE: if (start) begin
                    k_lat <= k_dim; p_pad <= ppad; done <= 0;
                    aclr <= ~accum;
                    state <= (k_dim == 0) ? DONE : INIT;
                end
                INIT: begin
                    sc <= 0; state <= STREAM;
                    wgt_cs <= 1; act_cs <= 1;
                end
                STREAM: begin
                    if (issuing) begin
                        wgt_addr <= sc; act_addr <= sc;
                    end
                    sc <= sc + 16'd1;
                    if (sc == p_pad + 16'd42) begin
                        state <= DONE; wgt_cs <= 0; act_cs <= 0;
                    end
                end
                DONE: begin
                    done <= 1;
                    if (start) begin
                        k_lat <= k_dim; p_pad <= ppad; done <= 0;
                        aclr <= ~accum;
                        state <= (k_dim == 0) ? DONE : INIT;
                    end
                end
            endcase
        end
    end
endmodule
