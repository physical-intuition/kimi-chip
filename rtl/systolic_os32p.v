// systolic_os32p - the 32x32 finale: paired output-stationary systolic
// array, 1024 PEs x 2 MACs/cycle = 2048 MACs/cycle sustained.
//
// Same dataflow as systolic_os16p, scaled: activations east, weights
// south, PE = int4_mac_v13f (registered pair-product; the multiply and
// the 13b chunk add in separate short stages -- the measured PE-local
// critical path this scale-up banks on). A 32-lane vector is TWO memory
// words, so each operand supplies FOUR words per cycle (lane-half x
// element-parity groups); rows/cols 0-15 tap the half-0 buffers,
// 16-31 the half-1. Transpose buffers are 32 deep (readers span 32
// skew cycles; the last reader hits a slot the same edge its overwrite
// lands -- nonblocking order keeps that safe, as in os16). Fold tag
// every 16 pairs (phase[3:0]==15); chunk bound unchanged. Injection
// gated on STREAM (the diagonal phantom-wave lesson).
//
// Capacity: 2048 elements per operand per pass (2 mem x 2048 x 128b =
// the same 64 KB); accum passes extend K to the 131,071 arithmetic
// bound. Throughput: K elements in K/2 + ~80 cycles.
module systolic_os32p (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire accum,
    input wire [15:0] k_dim,        // ELEMENTS this pass (<= 2048 usable)
    output reg  wgt_cs,
    output reg  [15:0] wgt_addr,    // PAIR index
    input wire [63:0] wgt_w00,      // half 0 (lanes 0-15),  element 2p
    input wire [63:0] wgt_w01,      // half 0,                element 2p+1
    input wire [63:0] wgt_w10,      // half 1 (lanes 16-31), element 2p
    input wire [63:0] wgt_w11,      // half 1,                element 2p+1
    output reg  act_cs,
    output reg  [15:0] act_addr,
    input wire [63:0] act_w00,
    input wire [63:0] act_w01,
    input wire [63:0] act_w10,
    input wire [63:0] act_w11,
    output wire [1024*24-1:0] acc_out,
    output reg done
);
    localparam IDLE=0, INIT=1, STREAM=2, DONE=3;
    reg [1:0]  state;
    reg [15:0] k_lat;
    reg [15:0] p_pad;
    reg [15:0] sc;
    reg        aclr;

    wire issuing = (state == STREAM) && (sc < p_pad);
    reg  [2:0] iv;
    reg  [4:0] kmod_p1, kmod_p2, kmod_p3;   // slot index, mod 32
    reg        az0_p1, az0_p2, az0_p3;
    reg        az1_p1, az1_p2, az1_p3;

    // ---- transpose buffers: [half][slot], per element parity ----
    reg [63:0] abuf0 [0:1][0:31];
    reg [63:0] abuf1 [0:1][0:31];
    reg [63:0] wbuf0 [0:1][0:31];
    reg [63:0] wbuf1 [0:1][0:31];
    always @(posedge clk) begin
        if (iv[2]) begin
            abuf0[0][kmod_p3] <= az0_p3 ? 64'd0 : act_w00;
            abuf0[1][kmod_p3] <= az0_p3 ? 64'd0 : act_w10;
            abuf1[0][kmod_p3] <= az1_p3 ? 64'd0 : act_w01;
            abuf1[1][kmod_p3] <= az1_p3 ? 64'd0 : act_w11;
            wbuf0[0][kmod_p3] <= wgt_w00;
            wbuf0[1][kmod_p3] <= wgt_w10;
            wbuf1[0][kmod_p3] <= wgt_w01;
            wbuf1[1][kmod_p3] <= wgt_w11;
        end
    end

    // ---- edge control: go pulse ripples along both 32-lane edges ----
    reg  [31:0] eact;
    reg  [4:0]  phase [0:31];
    reg  [15:0] wcnt  [0:31];
    reg  [31:0] ego;
    wire go0 = (state == STREAM) && (sc == 16'd3);
    integer x;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eact <= 0; ego <= 0;
        end else begin
            if (state == INIT) begin eact <= 0; ego <= 0; end
            else begin
                ego <= {ego[30:0], go0};
                for (x = 0; x < 32; x = x + 1) begin
                    if ((x == 0) ? go0 : ego[x-1]) begin
                        eact[x] <= 1'b1; phase[x] <= 0; wcnt[x] <= 0;
                    end else if (eact[x]) begin
                        phase[x] <= phase[x] + 5'd1;
                        wcnt[x]  <= wcnt[x] + 16'd1;
                    end
                end
            end
        end
    end

    // ---- operand/valid/tag pipes ----
    reg signed [3:0] Ax0 [0:31][0:31];
    reg signed [3:0] Ax1 [0:31][0:31];
    reg signed [3:0] Wx0 [0:31][0:31];
    reg signed [3:0] Wx1 [0:31][0:31];
    reg              Vx  [0:31][0:31];
    reg              Fx  [0:31][0:31];
    wire inj = (state == STREAM);
    integer i, j;
    always @(posedge clk) begin
        for (i = 0; i < 32; i = i + 1) begin
            for (j = 0; j < 32; j = j + 1) begin
                Ax0[i][j] <= (j == 0)
                    ? ((inj && eact[i] && (wcnt[i] < p_pad))
                        ? $signed(abuf0[i/16][phase[i]][(i%16)*4 +: 4]) : 4'sd0)
                    : Ax0[i][j-1];
                Ax1[i][j] <= (j == 0)
                    ? ((inj && eact[i] && (wcnt[i] < p_pad))
                        ? $signed(abuf1[i/16][phase[i]][(i%16)*4 +: 4]) : 4'sd0)
                    : Ax1[i][j-1];
                Wx0[i][j] <= (i == 0)
                    ? ((inj && eact[j] && (wcnt[j] < p_pad))
                        ? $signed(wbuf0[j/16][phase[j]][(j%16)*4 +: 4]) : 4'sd0)
                    : Wx0[i-1][j];
                Wx1[i][j] <= (i == 0)
                    ? ((inj && eact[j] && (wcnt[j] < p_pad))
                        ? $signed(wbuf1[j/16][phase[j]][(j%16)*4 +: 4]) : 4'sd0)
                    : Wx1[i-1][j];
                Vx[i][j] <= (j == 0)
                    ? (inj && eact[i] && (wcnt[i] < p_pad))
                    : Vx[i][j-1];
                Fx[i][j] <= (j == 0)
                    ? (inj && eact[i] && (wcnt[i] < p_pad) && (phase[i][3:0] == 4'd15))
                    : Fx[i][j-1];
            end
        end
    end

    generate genvar gr, gc;
        for (gr = 0; gr < 32; gr = gr + 1) begin : row
            for (gc = 0; gc < 32; gc = gc + 1) begin : col
                reg fq;
                always @(posedge clk) fq <= Fx[gr][gc];
                int4_mac_v13f mac (
                    .clk(clk), .rst_n(rst_n),
                    .en(Vx[gr][gc]), .clear(aclr), .drain(fq),
                    .a0(Ax0[gr][gc]), .a1(Ax1[gr][gc]),
                    .b0(Wx0[gr][gc]), .b1(Wx1[gr][gc]),
                    .acc(acc_out[(gr*32 + gc)*24 +: 24]));
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
            kmod_p1 <= sc[4:0];  kmod_p2 <= kmod_p1;  kmod_p3 <= kmod_p2;
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
                    // last pair enters lane 31 at ~p_pad+35; PE(31,31)
                    // finishes ~+31 later; fold pipeline +4; margin
                    if (sc == p_pad + 16'd76) begin
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
