// compute_core v13 - v11's control + v12's lane registers, PAIRED streaming:
// one element PAIR per cycle = 512 MACs/cycle sustained, 2x v10a.
//
// The memory system supplies 128 bits per operand per cycle (two 64-bit
// words: even/odd element of the pair). Addresses are PAIR indices; the
// core computes pairs = ceil(k_dim/2) and, when k_dim is odd, zeroes the
// odd activation slot of the final pair through the lane register (a1=0
// makes a1*b1 contribute nothing regardless of the garbage weight).
//
// Per-lane registers as v12 (placeable beside the strips; read latency
// grows by 1). MAC pipeline as v11: registered pair-product, chunk add on
// its own cycle, two-stage fold. FLUSH chain identical to v11.
module compute_core_v13 #(
    parameter RD_LAT = 3   // EXTERNAL memory latency (addr -> rdata ports)
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [15:0] k_dim,        // in ELEMENTS
    output reg wgt_cs,
    output reg [15:0] wgt_addr,     // PAIR index
    input wire [63:0] wgt_rdata0,
    input wire [63:0] wgt_rdata1,
    output reg act_cs,
    output reg [15:0] act_addr,     // PAIR index
    input wire [63:0] act_rdata0,
    input wire [63:0] act_rdata1,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam LAT = RD_LAT + 1;    // +1: the internal lane register stage
    localparam CHUNK = 16;          // pair-adds per fold: 16 x 128 = 2048 <= 4095 (13b chunk)
    localparam IDLE=0, CLEAR=1, RUN=2, FLUSH=3, FLUSH2=4, FLUSH3=5, FLUSH4=6, DONE=7;
    reg [2:0] state;
    reg [15:0] p_iss, pairs;
    reg half_k;                     // k_dim odd: final pair is half
    reg [LAT-1:0] vpipe;            // issue-valid, delayed to data-at-MAC
    reg [LAT-1:0] hpipe;            // half-pair marker, same alignment
    reg [3:0] addcnt;
    reg mac_clear, mac_drain;

    wire issuing    = (state == RUN) && (p_iss != pairs);
    wire half_issue = issuing && half_k && (p_iss == pairs - 16'd1);
    wire mac_en     = vpipe[LAT-1];
    wire hkill      = hpipe[LAT-2]; // gate lane reg capture of the odd slot

    // lane register tree (v12), doubled for the pair
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addcnt <= 0; mac_drain <= 0;
        end else if (mac_clear) begin
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
                IDLE: if (start) begin state <= CLEAR; mac_clear <= 1; done <= 0; end
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
                FLUSH: state <= FLUSH2;      // drain pulses into FLUSH2
                FLUSH2: state <= FLUSH3;     // MAC-internal add completes
                FLUSH3: state <= FLUSH4;     // fold stage captured
                FLUSH4: state <= DONE;       // wide add landed
                DONE: begin
                    done <= 1; wgt_cs <= 0; act_cs <= 0;
                    if (start) begin state <= CLEAR; mac_clear <= 1; done <= 0; end
                end
            endcase
        end
    end
endmodule
