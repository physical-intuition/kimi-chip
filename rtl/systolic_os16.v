// systolic_os16 - output-stationary 16x16 systolic array (v2 arc, M2).
//
// sys16 (M1) proved the clock (~935 MHz, critical path inside one PE)
// but stalls between chunks. M2 removes every stall by switching to the
// output-stationary form: ACTIVATIONS FLOW EAST, WEIGHTS FLOW SOUTH,
// one PE pitch per cycle, and each PE accumulates its own C[r][c] in
// place. Element k's activation enters row r after r skew cycles and
// reaches PE(r,c) after c more hops; its weight enters column c after c
// skew cycles and arrives after r hops -- both land at r+c: alignment
// is structural, k streams continuously, no weight-load phase exists.
//
// The PE arithmetic is int4_mac_v9 UNCHANGED (the verified chunked MAC:
// 12b chunk, 24b acc, fold every 16 adds): en rides with the activation
// as a valid bit; the fold tag is simply "phase == 15" injected at the
// west edge and delayed one cycle at the PE (v9 wants drain the cycle
// after the 16th add). K pads to a multiple of 16 with zeroed
// activation words, so stale weights contribute nothing.
//
// Transpose buffers: memory words arrive k-major (one word = all 16
// lanes of one k); edges consume lane-major. Each side keeps the last
// 16 words in a circular buffer; row r taps lane r of slot phase_r, a
// 4-bit 16:1 mux feeding a register -- an isolated path. Slot k is
// overwritten by word k+16 exactly one cycle after its last reader
// (row/col 15) uses it; nonblocking write order makes that safe.
//
// Throughput: K elements in K + ~42 cycles = 256 MACs/cycle sustained,
// fed by the same 2 words/cycle the memories already supply.
module systolic_os16 (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire accum,
    input wire [15:0] k_dim,
    output reg  wgt_cs,
    output reg  [15:0] wgt_addr,    // ELEMENT index
    input wire [63:0] wgt_word,     // valid 3 cycles after addr registers
    output reg  act_cs,
    output reg  [15:0] act_addr,
    input wire [63:0] act_word,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam IDLE=0, INIT=1, STREAM=2, DONE=3;
    reg [1:0]  state;
    reg [15:0] k_lat;               // K
    reg [15:0] k_pad;               // ceil(K/16)*16
    reg [15:0] sc;                  // stream cycle counter (= issue index)
    reg        aclr;

    // ---- issue + arrival pipes ----
    wire issuing = (state == STREAM) && (sc < k_pad);
    reg  [2:0] iv;                  // arrival pipe (word valid at +3)
    reg  [3:0] kmod_p1, kmod_p2, kmod_p3;
    reg        az_p1, az_p2, az_p3; // pad marker: zero the act word

    // ---- transpose buffers ----
    reg [63:0] abuf [0:15];
    reg [63:0] wbuf [0:15];
    integer x;
    always @(posedge clk) begin
        if (iv[2]) begin
            abuf[kmod_p3] <= az_p3 ? 64'd0 : act_word;
            wbuf[kmod_p3] <= wgt_word;
        end
    end

    // ---- edge phase/valid control: go pulse ripples along both edges ----
    reg  [15:0] eact;               // edge lane active
    reg  [3:0]  phase [0:15];
    reg  [15:0] wcnt  [0:15];       // words consumed by this lane
    reg  [15:0] ego;
    wire go0 = (state == STREAM) && (sc == 16'd3); // active during sc==4
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

    // ---- the array: operand/valid/tag pipes around int4_mac_v9 PEs ----
    reg signed [3:0] Ax [0:15][0:15]; // activations, east-flowing
    reg signed [3:0] Wx [0:15][0:15]; // weights, south-flowing
    reg              Vx [0:15][0:15]; // valid, east-flowing
    reg              Fx [0:15][0:15]; // fold tag, east-flowing
    // Injection is legal ONLY in STREAM: during INIT after a short pass,
    // stale eact/wcnt against the freshly-latched k_pad would fire one
    // phantom operand+valid wave from every lane edge; the east- and
    // south-going phantoms launch the same cycle and meet exactly on the
    // diagonal (r == c), silently corrupting only C[r][r]. Found by a
    // bank-crossing-style restart test; gate everything on STREAM.
    wire inj = (state == STREAM);
    integer i, j;
    always @(posedge clk) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                Ax[i][j] <= (j == 0)
                    ? ((inj && eact[i] && (wcnt[i] < k_pad))
                        ? $signed(abuf[phase[i]][i*4 +: 4]) : 4'sd0)
                    : Ax[i][j-1];
                Wx[i][j] <= (i == 0)
                    ? ((inj && eact[j] && (wcnt[j] < k_pad))
                        ? $signed(wbuf[phase[j]][j*4 +: 4]) : 4'sd0)
                    : Wx[i-1][j];
                Vx[i][j] <= (j == 0)
                    ? (inj && eact[i] && (wcnt[i] < k_pad))
                    : Vx[i][j-1];
                Fx[i][j] <= (j == 0)
                    ? (inj && eact[i] && (wcnt[i] < k_pad) && (phase[i] == 4'd15))
                    : Fx[i][j-1];
            end
        end
    end

    generate genvar gr, gc;
        for (gr = 0; gr < 16; gr = gr + 1) begin : row
            for (gc = 0; gc < 16; gc = gc + 1) begin : col
                reg fq;
                always @(posedge clk) fq <= Fx[gr][gc];
                int4_mac_v9 mac (
                    .clk(clk), .rst_n(rst_n),
                    .en(Vx[gr][gc]), .clear(aclr), .drain(fq),
                    .a(Ax[gr][gc]), .b(Wx[gr][gc]),
                    .acc(acc_out[(gr*16 + gc)*24 +: 24]));
            end
        end
    endgenerate

    // ---- FSM ----
    wire [15:0] pad = (k_dim + 16'd15) & 16'hFFF0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; done <= 0; aclr <= 0; sc <= 0;
            k_lat <= 0; k_pad <= 0;
            wgt_cs <= 0; act_cs <= 0; wgt_addr <= 0; act_addr <= 0;
            iv <= 0; kmod_p1 <= 0; kmod_p2 <= 0; kmod_p3 <= 0;
            az_p1 <= 0; az_p2 <= 0; az_p3 <= 0;
        end else begin
            aclr <= 0;
            iv <= {iv[1:0], issuing};
            kmod_p1 <= sc[3:0];  kmod_p2 <= kmod_p1;  kmod_p3 <= kmod_p2;
            az_p1 <= (sc >= k_lat); az_p2 <= az_p1;   az_p3 <= az_p2;
            case (state)
                IDLE: if (start) begin
                    k_lat <= k_dim; k_pad <= pad; done <= 0;
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
                    // last element enters row/col 15 at sc = k_pad+3+15+1;
                    // last compute at PE(15,15) ~ +15 more; fold +2; margin
                    if (sc == k_pad + 16'd40) begin
                        state <= DONE; wgt_cs <= 0; act_cs <= 0;
                    end
                end
                DONE: begin
                    done <= 1;
                    if (start) begin
                        k_lat <= k_dim; k_pad <= pad; done <= 0;
                        aclr <= ~accum;
                        state <= (k_dim == 0) ? DONE : INIT;
                    end
                end
            endcase
        end
    end
endmodule
