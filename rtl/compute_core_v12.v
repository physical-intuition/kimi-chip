// compute_core v12 - v10a + registered read-data broadcast (lane register tree).
//
// Routed evidence from fullchip_v10 (6_finish.rpt): the binding full-chip
// path is the read-data broadcast -- memory interface register -> array-
// interior MAC through mult + 12b add, all in ONE cycle -- a ~9% tax vs the
// 833 MHz core-only ceiling. v12 splits that cycle: every 4-bit lane of both
// operand buses gets its own register (16 per bus), placeable next to the
// row/column it feeds. Cycle N: rdata crosses the die into the lane
// register. Cycle N+1: local fanout + multiply + add. Lane registers have
// disjoint driver bits, so synthesis cannot merge the tree back into one.
//
// Total read latency grows to RD_LAT+1 and the issue-valid pipe stretches
// with it, so en and data are delayed together and control semantics are
// unchanged from v10a (single-add, CHUNK=16 folds, restart from DONE).
module compute_core_v12 #(
    parameter RD_LAT = 3   // EXTERNAL memory latency (addr -> rdata port)
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [15:0] k_dim,
    output reg wgt_cs,
    output reg [15:0] wgt_addr,
    input wire [63:0] wgt_rdata,
    output reg act_cs,
    output reg [15:0] act_addr,
    input wire [63:0] act_rdata,
    output wire [256*24-1:0] acc_out,
    output reg done
);
    localparam LAT = RD_LAT + 1;   // +1: the internal lane register stage
    localparam CHUNK = 16;
    localparam IDLE=0, CLEAR=1, RUN=2, FLUSH=3, FLUSH2=4, DONE=5;
    reg [2:0] state;
    reg [15:0] k_iss;
    reg [LAT-1:0] vpipe; // issue-valid, delayed to match data-at-MAC latency
    reg [3:0] addcnt;
    reg mac_clear, mac_drain;

    wire issuing = (state == RUN) && (k_iss != k_dim);
    wire mac_en  = vpipe[LAT-1];         // add exactly when lane regs are valid

    // lane register tree: weight lane c feeds column c, activation lane r
    // feeds row r; each lane's register can sit beside its strip.
    wire [63:0] wgt_bus, act_bus;
    genvar g;
    generate for (g = 0; g < 16; g = g + 1) begin : laneq
        reg [3:0] wq, aq;
        always @(posedge clk) begin
            wq <= wgt_rdata[g*4 +: 4];
            aq <= act_rdata[g*4 +: 4];
        end
        assign wgt_bus[g*4 +: 4] = wq;
        assign act_bus[g*4 +: 4] = aq;
    end endgenerate

    mac_array_v9 #(.ROWS(16), .COLS(16)) array (
        .clk(clk), .rst_n(rst_n),
        .en(mac_en), .clear(mac_clear), .drain(mac_drain),
        .activations(act_bus), .weights(wgt_bus), .acc_out(acc_out));

    // chunk bookkeeping: fold pulses the cycle after every CHUNK-th add
    // (concurrent adds are absorbed by the MACs' drain branch), plus a
    // final fold in FLUSH2 for the residual.
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
            state <= IDLE; k_iss <= 0; vpipe <= 0; done <= 0;
            mac_clear <= 0; wgt_cs <= 0; act_cs <= 0;
            wgt_addr <= 0; act_addr <= 0;
        end else begin
            vpipe <= {vpipe[LAT-2:0], issuing};
            case (state)
                IDLE: if (start) begin state <= CLEAR; mac_clear <= 1; done <= 0; end
                CLEAR: begin
                    mac_clear <= 0; k_iss <= 0; state <= RUN;
                    wgt_cs <= 1; act_cs <= 1;
                end
                RUN: begin
                    if (issuing) begin
                        wgt_addr <= k_iss; act_addr <= k_iss;
                        k_iss <= k_iss + 1;
                    end
                    // leave RUN once the last add has happened
                    if (!issuing && vpipe == {LAT{1'b0}}) state <= FLUSH;
                end
                FLUSH: state <= FLUSH2;      // drain pulses into FLUSH2
                FLUSH2: state <= DONE;
                DONE: begin
                    done <= 1; wgt_cs <= 0; act_cs <= 0;
                    if (start) begin state <= CLEAR; mac_clear <= 1; done <= 0; end
                end
            endcase
        end
    end
endmodule
