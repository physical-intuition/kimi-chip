// systolic_core16 - weight-stationary 16x16 systolic array ("sys16", M1).
//
// Computes the SAME C[r][c] = sum_k A[k][r]*W[k][c] as v9..v14, but with
// zero broadcast: every operand and partial sum moves one PE pitch per
// cycle. Per-cycle logic per PE = one 4x4 multiply + one 12-bit add +
// neighbor wire, fanout 1. This is the fmax thesis vehicle.
//
// Mapping (chunk t covers k = 16t..16t+15):
//   PE[i][j] holds w = W[16t+i][j], loaded via a down-shift chain fed in
//   reverse word order through a top staging register.
//   Row i's 64-bit buffer holds word A[16t+i][*] and lane-walks it: lane
//   r is presented at the row's west edge during cycle C+i+r (row skew =
//   a start pulse rippling down the rows; no register triangle).
//   A[i][0] captures the west value at end of that cycle; PE[i][j]
//   computes the (k=16t+i, r, j) term during cycle C+i+r+j+1; operand
//   and north psum both arrive +1 per hop, so alignment is structural.
//   P[15][j]'s r-term is ready at end of cycle C+16+r+j; bottom unit j
//   accumulates it during C+17+r+j (start pulse rippling east).
//
// M1 is stop-and-load: WLOAD (20 cycles) then inject+drain (49 cycles)
// per 16-element chunk -- deliberately; M1 exists to measure the clock.
// M2 (shadow weight regs + prefetch, swap riding the pipeline) removes
// every stall using the same 2 words/cycle the memories already supply.
//
// Bounds: |product| <= 64; column psum <= 16*64 = 1024 (12b signed);
// acc bound unchanged (total K <= 131071 across accum passes).
// Residual chunk: tail rows load ZERO activations, so stale weights
// contribute nothing.
module systolic_core16 (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire accum,               // sampled with start: keep accumulators
    input wire [15:0] k_dim,        // elements this pass
    // element-index read ports; *_word is valid 3 cycles after the cycle
    // whose end registers the address (v13/v14 memory timing)
    output reg  wgt_cs,
    output reg  [15:0] wgt_addr,    // ELEMENT index
    input wire [63:0] wgt_word,
    output reg  act_cs,
    output reg  [15:0] act_addr,
    input wire [63:0] act_word,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam IDLE=0, CLR=1, WLOAD=2, RUNC=3, DONE=4;
    reg [2:0]  state;
    reg [15:0] kt_base;
    reg [15:0] k_lat;
    reg [5:0]  cnt;
    reg        aclr;

    // ---- weight plane, top staging, activation row buffers ----
    reg  [63:0] wrow  [0:15];
    reg  [63:0] rowbuf[0:15];
    reg  [63:0] wtop;
    reg  [3:0]  wv;                 // issue -> +3 word valid -> +4 staged
    reg  [2:0]  av;
    reg  [3:0]  arow_p1, arow_p2, arow_p3;
    reg         azero_p1, azero_p2, azero_p3;

    // ---- row walk control ----
    reg  [15:0] walking;
    reg  [4:0]  wcnt [0:15];
    reg  [15:0] rowgo;
    wire inject0 = (state == RUNC) && (cnt == 0);
    wire [15:0] rpulse = {rowgo[14:0], inject0};
    wire [15:0] wact   = rpulse | walking;

    integer x;
    always @(posedge clk) begin
        if (wv[3]) begin
            wrow[0] <= wtop;
            for (x = 1; x < 16; x = x + 1) wrow[x] <= wrow[x-1];
        end
        wtop <= wgt_word;
        for (x = 0; x < 16; x = x + 1) begin
            if (av[2] && (arow_p3 == x[3:0]))
                rowbuf[x] <= azero_p3 ? 64'd0 : act_word;
            else if (wact[x])
                rowbuf[x] <= {4'd0, rowbuf[x][63:4]};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            walking <= 0; rowgo <= 0;
        end else begin
            rowgo <= {rowgo[14:0], inject0};
            for (x = 0; x < 16; x = x + 1) begin
                if (rpulse[x]) begin
                    walking[x] <= 1'b1; wcnt[x] <= 0;
                end else if (walking[x]) begin
                    wcnt[x] <= wcnt[x] + 5'd1;
                    if (wcnt[x] == 5'd14) walking[x] <= 1'b0;
                end
            end
        end
    end

    // ---- the array: one multiply + one 12b add + neighbor wire per PE ----
    reg signed [3:0]  Ar [0:15][0:15];
    reg signed [11:0] P  [0:15][0:15];
    integer i, j;
    always @(posedge clk) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                Ar[i][j] <= (j == 0)
                    ? (wact[i] ? $signed(rowbuf[i][3:0]) : 4'sd0)
                    : Ar[i][j-1];
                P[i][j] <= ((i == 0) ? 12'sd0 : P[i-1][j])
                    + Ar[i][j] * $signed(wrow[i][j*4 +: 4]);
            end
        end
    end

    // ---- bottom accumulator units ----
    reg  [15:0] bgo;
    reg  [4:0]  bcnt [0:15];
    reg  [15:0] bact;
    wire bot0 = (state == RUNC) && (cnt == 17);
    wire [15:0] bpulse = {bgo[14:0], bot0};
    generate genvar bj, br;
        for (bj = 0; bj < 16; bj = bj + 1) begin : bu
            reg signed [23:0] acc [0:15];
            integer y;
            wire [3:0] bidx = bpulse[bj] ? 4'd0 : bcnt[bj][3:0];
            always @(posedge clk) begin
                if (aclr) begin
                    for (y = 0; y < 16; y = y + 1) acc[y] <= 0;
                end else if (bpulse[bj] | bact[bj]) begin
                    acc[bidx] <= acc[bidx] + {{12{P[15][bj][11]}}, P[15][bj]};
                end
            end
            for (br = 0; br < 16; br = br + 1) begin : flat
                assign acc_out[(br*16 + bj)*24 +: 24] = acc[br];
            end
        end
    endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bgo <= 0; bact <= 0;
        end else begin
            bgo <= {bgo[14:0], bot0};
            for (x = 0; x < 16; x = x + 1) begin
                if (bpulse[x]) begin
                    bact[x] <= 1'b1; bcnt[x] <= 5'd1;
                end else if (bact[x]) begin
                    bcnt[x] <= bcnt[x] + 5'd1;
                    if (bcnt[x] == 5'd15) bact[x] <= 1'b0;
                end
            end
        end
    end

    // ---- FSM ----
    wire [15:0] rem = k_lat - kt_base;
    wire last_chunk = (rem <= 16);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; done <= 0; aclr <= 0; cnt <= 0;
            kt_base <= 0; k_lat <= 0;
            wgt_cs <= 0; act_cs <= 0; wgt_addr <= 0; act_addr <= 0;
            wv <= 0; av <= 0;
            arow_p1 <= 0; arow_p2 <= 0; arow_p3 <= 0;
            azero_p1 <= 0; azero_p2 <= 0; azero_p3 <= 0;
        end else begin
            aclr <= 0;
            wv <= {wv[2:0], (state == WLOAD) && (cnt < 16)};
            av <= {av[1:0], (state == WLOAD) && (cnt < 16)};
            arow_p1 <= cnt[3:0]; arow_p2 <= arow_p1; arow_p3 <= arow_p2;
            azero_p1 <= ({12'd0, cnt[3:0]} >= rem);
            azero_p2 <= azero_p1; azero_p3 <= azero_p2;
            case (state)
                IDLE: if (start) begin
                    k_lat <= k_dim; kt_base <= 0; done <= 0;
                    aclr <= ~accum;
                    state <= (k_dim == 0) ? DONE : CLR;
                end
                CLR: begin cnt <= 0; state <= WLOAD; wgt_cs <= 1; act_cs <= 1; end
                WLOAD: begin
                    if (cnt < 16) begin
                        wgt_addr <= kt_base + (16'd15 - {12'd0, cnt[3:0]});
                        act_addr <= kt_base + {12'd0, cnt[3:0]};
                    end
                    cnt <= cnt + 6'd1;
                    if (cnt == 6'd19) begin cnt <= 0; state <= RUNC; end
                end
                RUNC: begin
                    cnt <= cnt + 6'd1;
                    if (cnt == 6'd48) begin
                        if (last_chunk) begin
                            state <= DONE; wgt_cs <= 0; act_cs <= 0;
                        end else begin
                            kt_base <= kt_base + 16'd16;
                            cnt <= 0; state <= WLOAD;
                        end
                    end
                end
                DONE: begin
                    done <= 1;
                    if (start) begin
                        k_lat <= k_dim; kt_base <= 0; done <= 0;
                        aclr <= ~accum;
                        state <= (k_dim == 0) ? DONE : CLR;
                    end
                end
            endcase
        end
    end
endmodule
