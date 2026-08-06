// compute_core v10 - streaming control: ONE element per cycle.
//
// v4/v9 alternate FETCH/COMPUTE and sustain one element every 2 cycles.
// The SRAM read is fully pipelined, so v10 issues a new address every cycle
// and enables the accumulate exactly 2 cycles later (the read latency),
// giving one add per cycle once the pipeline fills: K elements in ~K+5
// cycles instead of ~2K+3. Same single-add semantics as v9 (en derives
// from a delayed issue-valid pipe, never from FSM dwell).
//
module compute_core_v11 #(
        parameter RD_LAT = 2   // SRAM read latency in cycles (vpipe depth)
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
    localparam CHUNK = 16;
    localparam IDLE=0, CLEAR=1, RUN=2, FLUSH=3, FLUSH2=4, FLUSH3=5, FLUSH4=6, DONE=7;
    reg [2:0] state;
    reg [15:0] k_iss;
    reg [RD_LAT-1:0] vpipe; // issue-valid, delayed to match SRAM latency
    reg [3:0] addcnt;
    reg mac_clear, mac_drain;

    wire issuing = (state == RUN) && (k_iss != k_dim);
    wire mac_en  = vpipe[RD_LAT-1];      // add exactly when rdata is valid

    mac_array_v11 #(.ROWS(16), .COLS(16)) array (
        .clk(clk), .rst_n(rst_n),
        .en(mac_en), .clear(mac_clear), .drain(mac_drain),
        .activations(act_rdata), .weights(wgt_rdata), .acc_out(acc_out));

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
            vpipe <= {vpipe[RD_LAT-2:0], issuing};
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
                    if (!issuing && vpipe == {RD_LAT{1'b0}}) state <= FLUSH;
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
